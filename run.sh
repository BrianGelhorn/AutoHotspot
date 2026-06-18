#!/usr/bin/env bash
set -euo pipefail

REAL_IFACE="wlp0s20f3"
AP_IFACE="ap0"

PUBLIC_WIFI=""
PUBLIC_WIFI_PASS=""

HOTSPOT_SSID="AutoHotspot"
HOTSPOT_PASS="AutoHotspot123"
HOTSPOT_SSID_PROVIDED=0
HOTSPOT_PASS_PROVIDED=0
SHARE_INTERNET=0

AP_IP="192.168.50.1"
AP_CIDR="192.168.50.1/24"
DHCP_START="192.168.50.10"
DHCP_END="192.168.50.100"

HOSTAPD_CONF="/tmp/autohotspot-hostapd.conf"
DNSMASQ_CONF="/tmp/autohotspot-dnsmasq.conf"
HOSTAPD_PID="/tmp/autohotspot-hostapd.pid"
DNSMASQ_PID="/tmp/autohotspot-dnsmasq.pid"

require_linux() {
    if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
        echo "Error: AutoHotspot must run on Linux."
        exit 1
    fi
}

require_privileges() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "[*] This script requires sudo privileges."
        sudo -v
        exec sudo -E bash "$0" "$@"
    fi
}

usage() {
    echo "Usage: sudo $0 [--ssid <hotspot-name> --password <hotspot-password>] [--wifi-ssid <wifi-name> --wifi-password <wifi-password>]"
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --ssid)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    echo "[ERROR] Missing value for --ssid."
                    usage
                    exit 1
                fi

                HOTSPOT_SSID="$2"
                HOTSPOT_SSID_PROVIDED=1
                shift 2
                ;;
            --password)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    echo "[ERROR] Missing value for --password."
                    usage
                    exit 1
                fi

                HOTSPOT_PASS="$2"
                HOTSPOT_PASS_PROVIDED=1
                shift 2
                ;;
            --wifi-ssid)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    echo "[ERROR] Missing value for --wifi-ssid."
                    usage
                    exit 1
                fi

                PUBLIC_WIFI="$2"
                shift 2
                ;;
            --wifi-password)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    echo "[ERROR] Missing value for --wifi-password."
                    usage
                    exit 1
                fi

                PUBLIC_WIFI_PASS="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "[ERROR] Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

validate_args() {
    if [[ -n "$PUBLIC_WIFI_PASS" && -z "$PUBLIC_WIFI" ]]; then
        echo "[ERROR] --wifi-password requires --wifi-ssid."
        usage
        exit 1
    fi
}

print_hotspot_defaults_notice() {
    if (( ! HOTSPOT_SSID_PROVIDED && ! HOTSPOT_PASS_PROVIDED )); then
        echo "[WARN] No hotspot --ssid or --password was provided."
        echo "[WARN] Using default hotspot credentials: SSID '$HOTSPOT_SSID', password '$HOTSPOT_PASS'."
    elif (( ! HOTSPOT_SSID_PROVIDED )); then
        echo "[WARN] No hotspot --ssid was provided. Using default SSID '$HOTSPOT_SSID'."
    elif (( ! HOTSPOT_PASS_PROVIDED )); then
        echo "[WARN] No hotspot --password was provided. Using default password '$HOTSPOT_PASS'."
    fi
}

current_wifi_connection() {
    nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | \
        awk -F: '$2 == "802-11-wireless" { print $1; exit }' || true
}

configure_networks() {
    local active_connection

    if [[ -n "$PUBLIC_WIFI" ]]; then
        SHARE_INTERNET=1
        return
    fi

    active_connection="$(current_wifi_connection)"

    if [[ -n "$active_connection" ]]; then
        PUBLIC_WIFI="$active_connection"
        SHARE_INTERNET=1
        return
    fi

    echo "[WARN] No active Wi-Fi network was found."
    echo "[WARN] The hotspot will be created without sharing an upstream network."
    echo "[WARN] To use a specific upstream Wi-Fi, pass --wifi-ssid and --wifi-password or connect to it before running this script."
}

package_for_dependency() {
    local dependency="$1"
    local package_manager="$2"

    case "$package_manager:$dependency" in
        apt-get:ip|pacman:ip)
            echo "iproute2"
            ;;
        dnf:ip)
            echo "iproute"
            ;;
        apt-get:nmcli)
            echo "network-manager"
            ;;
        dnf:nmcli)
            echo "NetworkManager"
            ;;
        pacman:nmcli)
            echo "networkmanager"
            ;;
        apt-get:awk)
            echo "mawk"
            ;;
        dnf:awk|pacman:awk)
            echo "gawk"
            ;;
        apt-get:pkill|apt-get:sysctl)
            echo "procps"
            ;;
        dnf:pkill|dnf:sysctl|pacman:pkill|pacman:sysctl)
            echo "procps-ng"
            ;;
        *:rm|*:tee|*:uname)
            echo "coreutils"
            ;;
        *)
            echo "$dependency"
            ;;
    esac
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        return 1
    fi
}

detect_package_manager_failure_reason() {
    local managers=(apk emerge nix-env xbps-install yum zypper)
    local found=()
    local manager

    for manager in "${managers[@]}"; do
        if command -v "$manager" >/dev/null 2>&1; then
            found+=("$manager")
        fi
    done

    if (( ${#found[@]} > 0 )); then
        echo "found unsupported package manager(s): ${found[*]}. Supported package managers are apt-get, dnf, and pacman."
    else
        echo "no supported package manager found in PATH. Supported package managers are apt-get, dnf, and pacman."
    fi
}

install_dependencies() {
    local dependencies=("$@")
    local package_manager
    local packages=()
    local output

    if ! package_manager="$(detect_package_manager)"; then
        echo "Could not install: ${dependencies[*]}"
        echo "Reason: $(detect_package_manager_failure_reason)"
        exit 1
    fi

    for dependency in "${dependencies[@]}"; do
        local package
        package="$(package_for_dependency "$dependency" "$package_manager")"

        if [[ " ${packages[*]} " != *" $package "* ]]; then
            packages+=("$package")
        fi
    done

    echo "[*] Installing missing dependencies: ${dependencies[*]}"

    case "$package_manager" in
        apt-get)
            if ! output="$(apt-get update 2>&1)"; then
                echo "Could not install: ${dependencies[*]}"
                echo "Reason: $output"
                exit 1
            fi

            if ! output="$(apt-get install -y "${packages[@]}" 2>&1)"; then
                echo "Could not install: ${dependencies[*]}"
                echo "Packages attempted: ${packages[*]}"
                echo "Reason: $output"
                exit 1
            fi
            ;;
        dnf)
            if ! output="$(dnf install -y "${packages[@]}" 2>&1)"; then
                echo "Could not install: ${dependencies[*]}"
                echo "Packages attempted: ${packages[*]}"
                echo "Reason: $output"
                exit 1
            fi
            ;;
        pacman)
            if ! output="$(pacman -Sy --noconfirm "${packages[@]}" 2>&1)"; then
                echo "Could not install: ${dependencies[*]}"
                echo "Packages attempted: ${packages[*]}"
                echo "Reason: $output"
                exit 1
            fi
            ;;
    esac
}

print_dependency_resolution_failure() {
    local dependencies=("$@")
    local package_manager
    local packages=()
    local outside_path=()
    local outside_dirs=()
    local unresolved=()
    local dependency
    local dir

    if package_manager="$(detect_package_manager 2>/dev/null)"; then
        for dependency in "${dependencies[@]}"; do
            local package
            package="$(package_for_dependency "$dependency" "$package_manager")"

            if [[ " ${packages[*]} " != *" $package "* ]]; then
                packages+=("$package")
            fi
        done
    fi

    for dependency in "${dependencies[@]}"; do
        local found=""

        for dir in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
            if [[ -x "$dir/$dependency" ]]; then
                found="$dir/$dependency"
                break
            fi
        done

        if [[ -n "$found" ]]; then
            outside_path+=("$found")
            dir="${found%/*}"

            if [[ " ${outside_dirs[*]} " != *" $dir "* ]]; then
                outside_dirs+=("$dir")
            fi
        else
            unresolved+=("$dependency")
        fi
    done

    if (( ${#outside_path[@]} > 0 )); then
        local path_dirs
        path_dirs="$(IFS=:; echo "${outside_dirs[*]}")"

        echo "Reason: some required commands exist, but this shell cannot find them."
        echo "Found: ${outside_path[*]}"
        echo "Fix: add these directories to PATH and run this script again: ${outside_dirs[*]}"
        echo "Example: export PATH=\"$path_dirs:\$PATH\""
    elif (( ${#packages[@]} > 0 )); then
        echo "Reason: the package manager reported success, but the required commands are still missing: ${unresolved[*]}"
        echo "Tried installing package(s): ${packages[*]}"
        echo "Fix: install the package that provides those command names on your distribution, then run this script again."
        echo "Tip: use your package manager to search which package provides '${unresolved[0]}'."
    else
        echo "Reason: required commands are still missing: ${unresolved[*]}"
        echo "Fix: install them manually with your distribution package manager, then run this script again."
    fi
}

require_dependencies() {
    local missing=()
    local still_missing=()
    local dependencies=(
        dnsmasq
        hostapd
        ip
        iptables
        iw
        nmcli
        awk
        pkill
        rfkill
        rm
        sysctl
        tee
        uname
    )

    for dependency in "${dependencies[@]}"; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            missing+=("$dependency")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        install_dependencies "${missing[@]}"
    fi

    for dependency in "${dependencies[@]}"; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            still_missing+=("$dependency")
        fi
    done

    if (( ${#still_missing[@]} > 0 )); then
        echo "Could not install or resolve: ${still_missing[*]}"
        print_dependency_resolution_failure "${still_missing[@]}"
        exit 1
    fi
}

parse_args "$@"
validate_args
require_linux
require_privileges "$@"
print_hotspot_defaults_notice
require_dependencies
configure_networks

if (( ${#HOTSPOT_PASS} < 8 )); then
    echo "[ERROR] The hotspot password must be at least 8 characters long. Use --password."
    exit 1
fi

echo "[*] Cleaning previous run..."
pkill -F "$HOSTAPD_PID" 2>/dev/null || true
pkill -F "$DNSMASQ_PID" 2>/dev/null || true
rm -f "$HOSTAPD_PID" "$DNSMASQ_PID"
iptables -t nat -D POSTROUTING -o "$REAL_IFACE" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i "$AP_IFACE" -o "$REAL_IFACE" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$REAL_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iw dev "$AP_IFACE" del 2>/dev/null || true

rfkill unblock wifi
nmcli radio wifi on

if (( SHARE_INTERNET )); then
    echo "[*] Using Wi-Fi upstream: $PUBLIC_WIFI"

    if [[ -n "$PUBLIC_WIFI_PASS" ]]; then
        nmcli device wifi connect "$PUBLIC_WIFI" password "$PUBLIC_WIFI_PASS" ifname "$REAL_IFACE"
    else
        nmcli connection up "$PUBLIC_WIFI" ifname "$REAL_IFACE" 2>/dev/null || \
            nmcli device wifi connect "$PUBLIC_WIFI" ifname "$REAL_IFACE"
    fi
fi

echo "[*] Creating virtual interface $AP_IFACE..."
iw dev "$REAL_IFACE" interface add "$AP_IFACE" type __ap
nmcli device set "$AP_IFACE" managed no 2>/dev/null || true
ip addr add "$AP_CIDR" dev "$AP_IFACE"

echo "[*] Writing configuration..."
tee "$HOSTAPD_CONF" >/dev/null <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=1
auth_algs=1
wpa=2
wpa_passphrase=$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

tee "$DNSMASQ_CONF" >/dev/null <<EOF
interface=$AP_IFACE
bind-dynamic
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,12h
dhcp-option=3,$AP_IP
dhcp-option=6,1.1.1.1,8.8.8.8
pid-file=$DNSMASQ_PID
EOF

if (( SHARE_INTERNET )); then
    echo "[*] Enabling NAT..."
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    iptables -t nat -A POSTROUTING -o "$REAL_IFACE" -j MASQUERADE
    iptables -A FORWARD -i "$AP_IFACE" -o "$REAL_IFACE" -j ACCEPT
    iptables -A FORWARD -i "$REAL_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
else
    echo "[*] Skipping NAT because no upstream Wi-Fi network is active."
fi

echo "[*] Starting services..."
hostapd -B -P "$HOSTAPD_PID" "$HOSTAPD_CONF"
dnsmasq --conf-file="$DNSMASQ_CONF"

echo
echo "[OK] Local network created."
echo "SSID: $HOTSPOT_SSID"
echo "PASS: $HOTSPOT_PASS"
echo "Gateway: $AP_IP"
echo "DHCP: $DHCP_START - $DHCP_END"
if (( SHARE_INTERNET )); then
    echo "Upstream: $PUBLIC_WIFI"
else
    echo "Upstream: none"
fi
