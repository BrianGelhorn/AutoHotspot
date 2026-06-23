#!/usr/bin/env bash
set -euo pipefail

REAL_IFACE=""
AP_IFACE="ap0"

PUBLIC_WIFI=""
PUBLIC_WIFI_PASS=""

HOTSPOT_SSID="AutoHotspot"
HOTSPOT_PASS="AutoHotspot123"
HOTSPOT_CHANNEL="1"
HOTSPOT_SSID_PROVIDED=0
HOTSPOT_PASS_PROVIDED=0
SHARE_INTERNET=0
STATUS_VERBOSE=0

AP_IP="192.168.50.1"
AP_CIDR="192.168.50.1/24"
DHCP_START="192.168.50.10"
DHCP_END="192.168.50.100"

HOSTAPD_CONF="/tmp/autohotspot-hostapd.conf"
DNSMASQ_CONF="/tmp/autohotspot-dnsmasq.conf"
HOSTAPD_PID="/tmp/autohotspot-hostapd.pid"
DNSMASQ_PID="/tmp/autohotspot-dnsmasq.pid"
DNSMASQ_LEASES="/tmp/autohotspot-dnsmasq.leases"
IP_FORWARD_STATE="/tmp/autohotspot-ip-forward.state"
COMMAND="start"

require_linux() {
    if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
        echo "Error: AutoHotspot must run on Linux."
        exit 1
    fi
}

require_privileges() {
    if [[ "$EUID" -ne 0 ]]; then
        if ! sudo -n true 2>/dev/null; then
            echo "[*] AutoHotspot needs administrator permissions to configure Wi-Fi interfaces, iptables, DHCP, and hostapd."
            sudo -v
        fi

        exec sudo -E bash "$0" "$@"
    fi
}

usage() {
    echo "Usage: sudo $0 [start|stop|status] [--interface <wifi-interface>] [--verbose] [--ssid <hotspot-name> --password <hotspot-password>] [--wifi-ssid <wifi-name> --wifi-password <wifi-password>]"
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            start|stop|status)
                COMMAND="$1"
                shift
                ;;
            --verbose)
                STATUS_VERBOSE=1
                shift
                ;;
            --interface)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    echo "[ERROR] Missing value for --interface."
                    usage
                    exit 1
                fi

                REAL_IFACE="$2"
                shift 2
                ;;
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

    if (( STATUS_VERBOSE )) && [[ "$COMMAND" != "status" ]]; then
        echo "[ERROR] --verbose is only supported with status."
        usage
        exit 1
    fi
}

print_hotspot_defaults_notice() {
    if [[ "$COMMAND" != "start" ]]; then
        return
    fi

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

current_wifi_channel() {
    local iface="$1"
    local channel

    if [[ -z "$iface" ]]; then
        return 1
    fi

    channel="$(iw dev "$iface" link 2>/dev/null | awk '/channel:/ { print $2; exit }')"
    if [[ -n "$channel" ]]; then
        echo "$channel"
        return 0
    fi

    channel="$(iw dev "$iface" info 2>/dev/null | awk '/channel/ { print $2; exit }')"
    if [[ -n "$channel" ]]; then
        echo "$channel"
        return 0
    fi

    channel="$(nmcli -t -f DEVICE,CHAN device status 2>/dev/null | awk -F: -v dev="$iface" '$1 == dev && $2 != "--" { print $2; exit }')"
    if [[ -n "$channel" ]]; then
        echo "$channel"
        return 0
    fi

    return 1
}

detect_hotspot_channel() {
    local channel

    channel="$(current_wifi_channel "$REAL_IFACE")" || return 1
    HOTSPOT_CHANNEL="$channel"
    echo "[*] Detected current Wi-Fi channel: $HOTSPOT_CHANNEL"
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

list_wireless_interfaces() {
    iw dev 2>/dev/null | awk '$1 == "Interface" { print $2 }'
}

select_real_interface() {
    local interfaces=()
    local iface

    if [[ -n "$REAL_IFACE" || "$COMMAND" != "start" ]]; then
        return
    fi

    while IFS= read -r iface; do
        interfaces+=("$iface")
    done < <(list_wireless_interfaces)

    if (( ${#interfaces[@]} > 0 )); then
        echo "[*] Available Wi-Fi interfaces:"
        printf '    %s\n' "${interfaces[@]}"
    else
        echo "[WARN] No Wi-Fi interfaces were detected automatically."
    fi

    if [[ ! -t 0 ]]; then
        echo "[ERROR] No --interface was provided and this shell is not interactive."
        usage
        exit 1
    fi

    while [[ -z "$REAL_IFACE" ]]; do
        read -r -p "Wi-Fi interface to use for the hotspot: " REAL_IFACE
        if [[ -z "$REAL_IFACE" ]]; then
            echo "[ERROR] Interface name cannot be empty."
        fi
    done
}

validate_real_interface() {
    if [[ -z "$REAL_IFACE" ]]; then
        return
    fi

    if ! ip link show dev "$REAL_IFACE" >/dev/null 2>&1; then
        echo "[ERROR] Interface '$REAL_IFACE' does not exist."
        exit 1
    fi

    if ! iw dev "$REAL_IFACE" info >/dev/null 2>&1; then
        echo "[ERROR] Interface '$REAL_IFACE' is not a Wi-Fi interface."
        exit 1
    fi
}

unblock_wifi() {
    if [[ ! -e /dev/rfkill ]]; then
        echo "[WARN] /dev/rfkill is not available; skipping rfkill unblock."
        echo "[WARN] If Wi-Fi is blocked, expose /dev/rfkill to the container or unblock Wi-Fi on the host."
        return
    fi

    if ! rfkill unblock wifi; then
        echo "[WARN] Could not unblock Wi-Fi with rfkill; continuing anyway."
        echo "[WARN] If Wi-Fi stays disabled, run 'rfkill unblock wifi' on the host and try again."
    fi
}

save_ip_forward_state() {
    if [[ ! -f "$IP_FORWARD_STATE" ]]; then
        sysctl -n net.ipv4.ip_forward >"$IP_FORWARD_STATE" 2>/dev/null || true
    fi
}

restore_ip_forward_state() {
    if [[ -f "$IP_FORWARD_STATE" ]]; then
        local previous_state
        previous_state="$(<"$IP_FORWARD_STATE")"

        if [[ "$previous_state" == "0" || "$previous_state" == "1" ]]; then
            sysctl -w "net.ipv4.ip_forward=$previous_state" >/dev/null 2>&1 || true
        fi

        rm -f "$IP_FORWARD_STATE"
    fi
}

cleanup_hotspot() {
    echo "[*] Cleaning AutoHotspot resources..."
    pkill -F "$HOSTAPD_PID" 2>/dev/null || true
    pkill -F "$DNSMASQ_PID" 2>/dev/null || true
    rm -f "$HOSTAPD_PID" "$DNSMASQ_PID" "$HOSTAPD_CONF" "$DNSMASQ_CONF" "$DNSMASQ_LEASES"
    if [[ -n "$REAL_IFACE" ]]; then
        iptables -t nat -D POSTROUTING -o "$REAL_IFACE" -j MASQUERADE 2>/dev/null || true
        iptables -D FORWARD -i "$AP_IFACE" -o "$REAL_IFACE" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i "$REAL_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    fi
    iw dev "$AP_IFACE" del 2>/dev/null || true
    restore_ip_forward_state
}

process_running_from_pidfile() {
    local pidfile="$1"
    local pid

    [[ -f "$pidfile" ]] || return 1
    pid="$(<"$pidfile")"
    [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]]
}

config_value() {
    local file="$1"
    local key="$2"
    local line

    [[ -f "$file" ]] || return 1

    while IFS= read -r line; do
        case "$line" in
            "$key="*)
                echo "${line#*=}"
                return 0
                ;;
        esac
    done <"$file"

    return 1
}

iptables_has_rule() {
    if [[ "$EUID" -eq 0 ]]; then
        iptables "$@" >/dev/null 2>&1
    elif sudo -n true 2>/dev/null; then
        sudo iptables "$@" >/dev/null 2>&1
    else
        return 2
    fi
}

print_rule_status() {
    local label="$1"
    shift

    if iptables_has_rule "$@"; then
        echo "$label: present"
    else
        case "$?" in
            2)
                echo "$label: unknown (administrator permissions required)"
                ;;
            *)
                echo "$label: missing"
                ;;
        esac
    fi
}

connected_client_count() {
    local station_count=""

    station_count="$(iw dev "$AP_IFACE" station dump 2>/dev/null | awk '/^Station / { count++ } END { print count + 0 }')" || station_count=""

    if [[ -n "$station_count" ]]; then
        echo "$station_count"
        return
    fi

    if [[ -f "$DNSMASQ_LEASES" ]]; then
        awk 'NF > 0 { count++ } END { print count + 0 }' "$DNSMASQ_LEASES"
        return
    fi

    echo 0
}

print_status() {
    local hostapd_status="stopped"
    local dnsmasq_status="stopped"
    local ap_status="missing"
    local ap_ip_status="missing"
    local overall_status="stopped"
    local ssid="unknown"
    local ip_forward="unknown"
    local upstream="none"
    local internet_sharing="no"
    local connected_clients="0"

    if process_running_from_pidfile "$HOSTAPD_PID"; then
        hostapd_status="running"
    fi

    if process_running_from_pidfile "$DNSMASQ_PID"; then
        dnsmasq_status="running"
    fi

    if iw dev "$AP_IFACE" info >/dev/null 2>&1; then
        ap_status="present"
    fi

    if ip addr show dev "$AP_IFACE" 2>/dev/null | awk -v cidr="$AP_CIDR" '$1 == "inet" && $2 == cidr { found = 1 } END { exit !found }'; then
        ap_ip_status="present"
    fi

    ssid="$(config_value "$HOSTAPD_CONF" ssid || echo "unknown")"
    ip_forward="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "unknown")"
    upstream="$(current_wifi_connection)"
    connected_clients="$(connected_client_count)"

    if [[ -z "$upstream" ]]; then
        upstream="none"
    fi

    if [[ "$hostapd_status" == "running" && "$dnsmasq_status" == "running" && "$ap_status" == "present" ]]; then
        overall_status="running"
    elif [[ "$hostapd_status" == "running" || "$dnsmasq_status" == "running" || "$ap_status" == "present" ]]; then
        overall_status="partial"
    fi

    if [[ "$overall_status" == "stopped" ]]; then
        internet_sharing="no"
    elif [[ -n "$REAL_IFACE" ]] && iptables_has_rule -t nat -C POSTROUTING -o "$REAL_IFACE" -j MASQUERADE; then
        if [[ "$ip_forward" == "1" && "$upstream" != "none" ]]; then
            internet_sharing="yes, from $upstream"
        else
            internet_sharing="partial"
        fi
    elif [[ -z "$REAL_IFACE" ]]; then
        internet_sharing="unknown (use --interface to check NAT rules)"
    else
        case "$?" in
            2)
                if [[ "$upstream" != "none" ]]; then
                    internet_sharing="unknown, upstream is $upstream (administrator permissions required to check NAT)"
                else
                    internet_sharing="unknown (administrator permissions required)"
                fi
                ;;
            *)
                internet_sharing="no"
                ;;
        esac
    fi

    echo "AutoHotspot status"
    echo "State: $overall_status"
    echo "SSID: $ssid"
    echo "AP interface ($AP_IFACE): $ap_status"
    echo "Gateway: $AP_IP"
    echo "Internet sharing: $internet_sharing"
    echo "Connected devices: $connected_clients"

    if (( ! STATUS_VERBOSE )); then
        return
    fi

    echo "hostapd: $hostapd_status"
    echo "dnsmasq: $dnsmasq_status"
    echo "AP address ($AP_CIDR): $ap_ip_status"
    echo "ip_forward: $ip_forward"
    echo "Upstream Wi-Fi: $upstream"
    echo "DHCP leases: $DNSMASQ_LEASES"
    if [[ -n "$REAL_IFACE" ]]; then
        print_rule_status "NAT rule" -t nat -C POSTROUTING -o "$REAL_IFACE" -j MASQUERADE
        print_rule_status "Forward AP to upstream" -C FORWARD -i "$AP_IFACE" -o "$REAL_IFACE" -j ACCEPT
        print_rule_status "Forward upstream to AP" -C FORWARD -i "$REAL_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    else
        echo "NAT rule: unknown (use --interface to check)"
        echo "Forward AP to upstream: unknown (use --interface to check)"
        echo "Forward upstream to AP: unknown (use --interface to check)"
    fi

    if [[ -f "$IP_FORWARD_STATE" ]]; then
        echo "Saved ip_forward state: $(<"$IP_FORWARD_STATE")"
    else
        echo "Saved ip_forward state: none"
    fi
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

if [[ "$COMMAND" == "status" ]]; then
    print_status
    exit 0
fi

require_privileges "$@"
print_hotspot_defaults_notice
require_dependencies
select_real_interface
validate_real_interface

if [[ "$COMMAND" == "stop" ]]; then
    cleanup_hotspot
    echo "[OK] AutoHotspot stopped."
    exit 0
fi

configure_networks

if (( ${#HOTSPOT_PASS} < 8 )); then
    echo "[ERROR] The hotspot password must be at least 8 characters long. Use --password."
    exit 1
fi

cleanup_hotspot

unblock_wifi
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

if ! detect_hotspot_channel; then
    echo "[WARN] No current Wi-Fi channel detected; using default channel $HOTSPOT_CHANNEL."
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
channel=$HOTSPOT_CHANNEL
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
dhcp-leasefile=$DNSMASQ_LEASES
EOF

if (( SHARE_INTERNET )); then
    echo "[*] Enabling NAT..."
    save_ip_forward_state
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
