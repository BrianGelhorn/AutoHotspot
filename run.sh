#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  autohotspot start [--interface IFACE] [--ssid NAME] [--password PASS] [--upstream IFACE] [--share-internet]
  autohotspot stop
  autohotspot restart
  autohotspot status
  autohotspot doctor
USAGE
}

die() {
  echo "autohotspot: $*" >&2
  echo >&2
  usage >&2
  exit 2
}

need_value() {
  [[ $# -gt 1 && $2 != --* ]] || die "$1 requires a value"
}

require_root() {
  [[ $EUID -eq 0 ]] && return
  command -v sudo >/dev/null 2>&1 || die "sudo is required"
  exec sudo -- "$0" "$@"
}

nmcli_cmd() {
  "${AUTOHOTSPOT_NMCLI:-nmcli}" "$@"
}

iw_cmd() {
  "${AUTOHOTSPOT_IW:-iw}" "$@"
}

list_wifi_interfaces() {
  nmcli_cmd -t -f DEVICE,TYPE device status | awk -F: '$2 == "wifi" { print $1 }'
}

select_interface() {
  local hotspot_interface=$1
  local interfaces=()
  local interface

  if [[ -n $hotspot_interface ]]; then
    echo "$hotspot_interface"
    return
  fi

  while IFS= read -r interface; do
    interfaces+=("$interface")
  done < <(list_wifi_interfaces)

  if [[ ${#interfaces[@]} -eq 1 ]]; then
    echo "${interfaces[0]}"
    return
  fi

  [[ ${#interfaces[@]} -gt 0 ]] || die "no Wi-Fi interfaces found"

  echo "Available Wi-Fi interfaces:" >&2
  printf '  %s\n' "${interfaces[@]}" >&2

  while [[ -z $hotspot_interface ]]; do
    read -r -p "Hotspot interface: " hotspot_interface || die "--interface is required"
  done

  echo "$hotspot_interface"
}

cleanup_hotspot() {
  nmcli_cmd connection down AutoHotspot >/dev/null 2>&1 || true
  nmcli_cmd connection delete AutoHotspot >/dev/null 2>&1 || true
  command -v "${AUTOHOTSPOT_IW:-iw}" >/dev/null 2>&1 && iw_cmd dev ap0 del >/dev/null 2>&1 || true
}

stop() {
  [[ $# -eq 0 ]] || die "stop does not accept arguments yet"
  command -v "${AUTOHOTSPOT_NMCLI:-nmcli}" >/dev/null 2>&1 || die "nmcli is required"

  cleanup_hotspot
  echo "AutoHotspot stopped"
}

start_ap() {
  local hotspot_interface=$1
  local ssid=$2
  local password=$3
  local connection_name=AutoHotspot

  nmcli_cmd connection add type wifi ifname "$hotspot_interface" con-name "$connection_name" autoconnect no ssid "$ssid"
  nmcli_cmd connection modify "$connection_name" 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
  nmcli_cmd connection modify "$connection_name" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$password"
  nmcli_cmd connection up "$connection_name" ifname "$hotspot_interface"
}

start() {
  local hotspot_interface="" ssid="" password="" upstream="" share_internet=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interface)
        need_value "$@"; hotspot_interface=$2; shift 2 ;;
      --ssid)
        need_value "$@"; ssid=$2; shift 2 ;;
      --password|--passphrase)
        need_value "$@"; password=$2; shift 2 ;;
      --upstream)
        need_value "$@"; upstream=$2; shift 2 ;;
      --share-internet)
        share_internet=true; shift ;;
      --help|-h)
        usage; exit 0 ;;
      *)
        die "unknown start argument: $1" ;;
    esac
  done

  command -v "${AUTOHOTSPOT_NMCLI:-nmcli}" >/dev/null 2>&1 || die "nmcli is required"

  cleanup_hotspot
  hotspot_interface=$(select_interface "$hotspot_interface")

  if [[ -z $ssid || -z $password ]]; then
    echo "Missing SSID or passphrase. Using defaults for missing values."
    [[ -n $ssid ]] || ssid="AutoHotspot"
    [[ -n $password ]] || password="AutoHotspot12321"
  fi

  [[ ${#password} -ge 8 ]] || die "--password must be at least 8 characters"

  start_ap "$hotspot_interface" "$ssid" "$password"

  echo "AutoHotspot started"
  echo "Interface: $hotspot_interface"
  echo "SSID: $ssid"
  echo "Passphrase: $password"
}

no_args() {
  local command=$1
  shift
  [[ $# -eq 0 ]] || die "$command does not accept arguments yet"
  echo "$command: not implemented"
}

main() {
  [[ $# -gt 0 ]] || die "missing command"

  case "$1" in
    start)
      require_root "$@"
      shift; start "$@" ;;
    stop)
      require_root "$@"
      shift; stop "$@" ;;
    restart|status|doctor)
      no_args "$@" ;;
    --help|-h|help)
      usage ;;
    *)
      die "unknown command: $1" ;;
  esac
}

main "$@"
