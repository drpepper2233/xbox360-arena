#!/usr/bin/env bash
set -euo pipefail

# Host-side operator control for moving the RTX 3090 Ti runtime slot between:
# - VM 100: AI video lab / videogen
# - VM 360: x360-arena
#
# Run on bigbrother, or pipe over ssh:
#   ssh root@192.168.0.25 'bash -s -- xbox-on --yes' < deploy/control.sh

HOST_NAME="bigbrother"
HOST_IP="192.168.0.25"

VIDEO_VM_ID="100"
VIDEO_VM_NAME="ai-video-lab"

ARENA_VM_ID="360"
ARENA_VM_NAME="x360-arena"

GPU_PCI="0000:2d:00"
GPU_HOSTPCI_VALUE="${GPU_PCI},pcie=1,x-vga=1"

WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-180}"
POLL_SECONDS="${POLL_SECONDS:-2}"
ARENA_GUEST_HOST="${ARENA_GUEST_HOST:-<vm-360-guest-ip>}"

YES=false
COMMAND=""

usage() {
  cat <<USAGE
Usage:
  control.sh [--yes] xbox-on
  control.sh [--yes] xbox-off
  control.sh status

Commands:
  xbox-on   Stop VM ${VIDEO_VM_ID} if needed, attach GPU ${GPU_PCI} to VM ${ARENA_VM_ID}, start VM ${ARENA_VM_ID}.
  xbox-off  Stop VM ${ARENA_VM_ID} if needed, detach GPU from VM ${ARENA_VM_ID}, start VM ${VIDEO_VM_ID}.
  status    Show VM power state, hostpci0 ownership, and a one-line summary.

Options:
  -y, --yes  Skip the xbox-on confirmation banner before powering off VM ${VIDEO_VM_ID}.
  -h, --help Show this help.

Environment:
  ARENA_GUEST_HOST          Hostname or IP used when printing stream URLs.
  WAIT_TIMEOUT_SECONDS      VM start/stop wait timeout. Default: ${WAIT_TIMEOUT_SECONDS}.
  POLL_SECONDS              VM status poll interval. Default: ${POLL_SECONDS}.

Run context:
  This script must run on ${HOST_NAME} (${HOST_IP}) with the Proxmox qm CLI available.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_qm() {
  # command -v verifies the Proxmox qm CLI exists before any VM operation.
  command -v qm >/dev/null 2>&1 || die "qm not found; run this on ${HOST_NAME} (${HOST_IP}) or via ssh root@${HOST_IP}"
}

vm_status() {
  local vmid="$1"
  local line

  # qm status reads the current VM power state from Proxmox.
  line="$(qm status "$vmid")"
  printf '%s\n' "${line#status: }"
}

vm_config() {
  local vmid="$1"

  # qm config reads VM hardware config, including hostpci0 ownership.
  qm config "$vmid"
}

hostpci0_value() {
  local vmid="$1"
  local config

  config="$(vm_config "$vmid")"
  awk -F': ' '$1 == "hostpci0" { print $2; exit }' <<<"$config"
}

hostpci_holds_gpu() {
  local value="${1:-}"
  [[ "$value" == *"$GPU_PCI"* ]]
}

hostpci_matches_arena_value() {
  local value="${1:-}"
  [[ "$value" == *"$GPU_PCI"* && "$value" == *"pcie=1"* && "$value" == *"x-vga=1"* ]]
}

wait_for_vm_status() {
  local vmid="$1"
  local expected="$2"
  local label="$3"
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
  local current

  while (( SECONDS < deadline )); do
    current="$(vm_status "$vmid")"
    if [[ "$current" == "$expected" ]]; then
      printf '%s (VM %s) is %s.\n' "$label" "$vmid" "$expected"
      return 0
    fi
    sleep "$POLL_SECONDS"
  done

  die "timed out waiting for ${label} (VM ${vmid}) to become ${expected}; last state: ${current:-unknown}"
}

ensure_vm_stopped() {
  local vmid="$1"
  local label="$2"
  local current

  current="$(vm_status "$vmid")"
  if [[ "$current" == "stopped" ]]; then
    printf '%s (VM %s) is already stopped.\n' "$label" "$vmid"
    return 0
  fi

  printf 'Stopping %s (VM %s), current state: %s.\n' "$label" "$vmid" "$current"
  # qm stop powers off the VM before GPU ownership changes.
  qm stop "$vmid"
  wait_for_vm_status "$vmid" "stopped" "$label"
}

ensure_vm_running() {
  local vmid="$1"
  local label="$2"
  local current

  current="$(vm_status "$vmid")"
  if [[ "$current" == "running" ]]; then
    printf '%s (VM %s) is already running.\n' "$label" "$vmid"
    return 0
  fi

  if [[ "$current" != "stopped" ]]; then
    ensure_vm_stopped "$vmid" "$label"
  fi

  printf 'Starting %s (VM %s).\n' "$label" "$vmid"
  # qm start powers on the VM after GPU ownership is safe.
  qm start "$vmid"
  wait_for_vm_status "$vmid" "running" "$label"
}

confirm_video_lab_poweroff() {
  local reply

  if [[ "$YES" == "true" ]]; then
    return 0
  fi

  cat >&2 <<BANNER

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!! XBOX-ON WILL POWER OFF THE AI VIDEO LAB: VM ${VIDEO_VM_ID} (${VIDEO_VM_NAME})
!!! GPU ${GPU_PCI} IS EXCLUSIVE AND WILL BE USED BY VM ${ARENA_VM_ID} (${ARENA_VM_NAME})
!!! UNSAVED WORK INSIDE VM ${VIDEO_VM_ID} CAN BE LOST.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

BANNER
  printf 'Type POWER OFF VM %s to continue: ' "$VIDEO_VM_ID" >&2
  if ! read -r reply; then
    die "confirmation required"
  fi

  [[ "$reply" == "POWER OFF VM ${VIDEO_VM_ID}" ]] || die "confirmation did not match; aborting"
}

ensure_arena_gpu_attached() {
  local current
  local arena_state

  current="$(hostpci0_value "$ARENA_VM_ID")"
  if hostpci_matches_arena_value "$current"; then
    printf '%s (VM %s) already has hostpci0=%s.\n' "$ARENA_VM_NAME" "$ARENA_VM_ID" "$current"
    return 0
  fi

  arena_state="$(vm_status "$ARENA_VM_ID")"
  if [[ "$arena_state" != "stopped" ]]; then
    printf '%s (VM %s) must restart to apply hostpci0=%s.\n' "$ARENA_VM_NAME" "$ARENA_VM_ID" "$GPU_HOSTPCI_VALUE"
    ensure_vm_stopped "$ARENA_VM_ID" "$ARENA_VM_NAME"
  fi

  printf 'Setting %s (VM %s) hostpci0=%s.\n' "$ARENA_VM_NAME" "$ARENA_VM_ID" "$GPU_HOSTPCI_VALUE"
  # qm set assigns RTX 3090 Ti passthrough to x360-arena hostpci0.
  qm set "$ARENA_VM_ID" --hostpci0 "$GPU_HOSTPCI_VALUE"
}

ensure_arena_gpu_detached() {
  local current

  current="$(hostpci0_value "$ARENA_VM_ID")"
  if [[ -z "$current" ]]; then
    printf '%s (VM %s) has no hostpci0 configured.\n' "$ARENA_VM_NAME" "$ARENA_VM_ID"
    return 0
  fi

  printf 'Deleting %s (VM %s) hostpci0=%s.\n' "$ARENA_VM_NAME" "$ARENA_VM_ID" "$current"
  # qm set --delete removes hostpci0 from x360-arena before restoring VM 100.
  qm set "$ARENA_VM_ID" --delete hostpci0
}

append_csv() {
  local current="$1"
  local item="$2"

  if [[ -z "$current" ]]; then
    printf '%s' "$item"
  else
    printf '%s, %s' "$current" "$item"
  fi
}

print_stream_urls() {
  printf 'Open in Chrome: http://%s:8080\n' "$ARENA_GUEST_HOST"
  printf 'Sunshine pairing UI: https://%s:47990\n' "$ARENA_GUEST_HOST"
}

status_summary() {
  local video_state="$1"
  local arena_state="$2"
  local video_hostpci="$3"
  local arena_hostpci="$4"
  local configured_holders=""
  local active_holders=""

  if hostpci_holds_gpu "$video_hostpci"; then
    configured_holders="$(append_csv "$configured_holders" "VM ${VIDEO_VM_ID} (${VIDEO_VM_NAME})")"
    if [[ "$video_state" == "running" ]]; then
      active_holders="$(append_csv "$active_holders" "VM ${VIDEO_VM_ID} (${VIDEO_VM_NAME})")"
    fi
  fi

  if hostpci_holds_gpu "$arena_hostpci"; then
    configured_holders="$(append_csv "$configured_holders" "VM ${ARENA_VM_ID} (${ARENA_VM_NAME})")"
    if [[ "$arena_state" == "running" ]]; then
      active_holders="$(append_csv "$active_holders" "VM ${ARENA_VM_ID} (${ARENA_VM_NAME})")"
    fi
  fi

  configured_holders="${configured_holders:-none}"
  active_holders="${active_holders:-none}"

  printf 'summary: VM %s=%s; VM %s=%s; configured GPU holder(s)=%s; active GPU holder(s)=%s\n' \
    "$VIDEO_VM_ID" "$video_state" "$ARENA_VM_ID" "$arena_state" "$configured_holders" "$active_holders"
}

show_status() {
  local video_state
  local arena_state
  local video_hostpci
  local arena_hostpci

  require_qm

  video_state="$(vm_status "$VIDEO_VM_ID")"
  arena_state="$(vm_status "$ARENA_VM_ID")"
  video_hostpci="$(hostpci0_value "$VIDEO_VM_ID")"
  arena_hostpci="$(hostpci0_value "$ARENA_VM_ID")"

  printf 'Host: %s (%s)\n' "$HOST_NAME" "$HOST_IP"
  printf 'VM %s (%s): status=%s hostpci0=%s\n' "$VIDEO_VM_ID" "$VIDEO_VM_NAME" "$video_state" "${video_hostpci:-<none>}"
  printf 'VM %s (%s): status=%s hostpci0=%s\n' "$ARENA_VM_ID" "$ARENA_VM_NAME" "$arena_state" "${arena_hostpci:-<none>}"
  status_summary "$video_state" "$arena_state" "$video_hostpci" "$arena_hostpci"
}

xbox_on() {
  local video_state

  require_qm

  video_state="$(vm_status "$VIDEO_VM_ID")"
  if [[ "$video_state" != "stopped" ]]; then
    confirm_video_lab_poweroff
    ensure_vm_stopped "$VIDEO_VM_ID" "$VIDEO_VM_NAME"
  else
    printf '%s (VM %s) is already stopped.\n' "$VIDEO_VM_NAME" "$VIDEO_VM_ID"
  fi

  ensure_arena_gpu_attached
  ensure_vm_running "$ARENA_VM_ID" "$ARENA_VM_NAME"
  print_stream_urls
  show_status
}

xbox_off() {
  require_qm

  ensure_vm_stopped "$ARENA_VM_ID" "$ARENA_VM_NAME"
  ensure_arena_gpu_detached
  ensure_vm_running "$VIDEO_VM_ID" "$VIDEO_VM_NAME"
  show_status
}

parse_args() {
  while (($#)); do
    case "$1" in
      -y|--yes)
        YES=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      xbox-on|xbox-off|status)
        [[ -z "$COMMAND" ]] || die "multiple commands supplied: ${COMMAND} and $1"
        COMMAND="$1"
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  [[ -n "$COMMAND" ]] || {
    usage >&2
    exit 2
  }
}

main() {
  parse_args "$@"

  case "$COMMAND" in
    xbox-on)
      xbox_on
      ;;
    xbox-off)
      xbox_off
      ;;
    status)
      show_status
      ;;
    *)
      die "unhandled command: $COMMAND"
      ;;
  esac
}

main "$@"
