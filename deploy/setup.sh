#!/usr/bin/env bash
# Xbox 360 Arena — single operator entrypoint (host-side orchestrator).
#
# Builds, end to end, a Windows 11 VM on a Proxmox host with RTX 3090 Ti passthrough,
# the Xenia Canary emulator, and Sunshine + Moonlight Web browser streaming.
# These are the REAL commands that produced the working 2026-06-23 deployment, parameterised.
#
# Run from a machine that can ssh to the Proxmox host. Requires: ssh, scp, sshpass, genisoimage
# (or xorriso). The Windows + virtio ISOs must already be on the host (see PROV step).
#
# Usage:
#   deploy/setup.sh provision   # create VM + answer ISO + start unattended Windows install
#   deploy/setup.sh software    # push payload + run guest-setup.ps1 (emulator + streaming stack)
#   deploy/setup.sh gpu         # bind the GPU (control.sh xbox-on) + install NVIDIA driver + NVENC
#   deploy/setup.sh all         # provision -> wait for SSH -> software -> gpu
#   deploy/setup.sh status      # show VM + stream reachability
set -euo pipefail

# ---- Config (override via environment) -------------------------------------------------------
PVE_HOST="${PVE_HOST:-192.168.0.25}"          # Proxmox host (bigbrother)
PVE_USER="${PVE_USER:-root}"
PVE_PASS="${PVE_PASS:-<HOST_ROOT_PASSWORD — see deploy/SECRETS.md>}"
VMID="${VMID:-360}"
VMNAME="${VMNAME:-x360-arena}"
GPU_PCI="${GPU_PCI:-0000:2d:00}"              # RTX 3090 Ti (reuse from `qm config <video-vm>`)
VIDEO_VMID="${VIDEO_VMID:-100}"               # VM that normally holds the GPU (ai-video-lab)
GUEST_USER="${GUEST_USER:-arena}"
GUEST_PASS="${GUEST_PASS:-<ARENA_PASSWORD — see deploy/SECRETS.md>}"
WIN_ISO="${WIN_ISO:-local:iso/Win11_25H2_English_x64.iso}"
VIRTIO_ISO="${VIRTIO_ISO:-local:iso/virtio-win.iso}"
HTTP_PORT="${HTTP_PORT:-8099}"                # host LAN mirror for guest downloads

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PVE_SSH=(sshpass -p "$PVE_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$PVE_USER@$PVE_HOST")
PVE_SCP=(sshpass -p "$PVE_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

log() { echo -e "\n=== $* ==="; }

guest_ip() { "${PVE_SSH[@]}" "qm guest cmd $VMID network-get-interfaces 2>/dev/null" \
  | grep -oE '192\.168\.[0-9.]+' | grep -v '\.255$' | head -1; }

provision() {
  log "PROVISION VM $VMID on $PVE_HOST"
  "${PVE_SSH[@]}" "bash -s" <<EOF
set -e
qm create $VMID --name $VMNAME --machine q35 --bios ovmf --cpu host --cores 16 --memory 32768 \
  --scsihw virtio-scsi-pci --net0 virtio,bridge=vmbr0 --ostype win11 --agent 1
qm set $VMID --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=1
qm set $VMID --tpmstate0 local-lvm:1,version=v2.0
qm set $VMID --scsi0 local-lvm:256,discard=on,ssd=1
qm set $VMID --ide2 $WIN_ISO,media=cdrom --ide0 $VIRTIO_ISO,media=cdrom
EOF
  log "BUILD answer ISO (autounattend + payload) and attach"
  build_answer_iso
  "${PVE_SSH[@]}" "qm set $VMID --ide3 local:iso/x360-answer.iso,media=cdrom; qm set $VMID --boot order='ide2;scsi0;ide0;ide3'; qm start $VMID"
  log "Windows is installing unattended. NOTE: the Win11 ISO shows 'Press any key to boot from CD' —"
  echo "  if the install doesn't start, flood Enter via: qm sendkey $VMID ret (a few times right after boot)."
  echo "  bootstrap.ps1 self-elevates, installs OpenSSH (from GitHub zip), and runs guest-setup at first logon."
}

build_answer_iso() {
  local pw_esc; pw_esc="$GUEST_PASS"
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/deploy" "$tmp/config"
  cp "$REPO_ROOT"/deploy/*.ps1 "$tmp/deploy/" 2>/dev/null || true
  cp "$REPO_ROOT/deploy/autounattend.xml" "$tmp/autounattend.xml"
  cp -r "$REPO_ROOT/config/." "$tmp/config/"
  # Inject the admin password into the answer file copy (never committed to git).
  sed -i.bak "s/PLACEHOLDER_REPLACE_WITH_ARENA_PASSWORD/$pw_esc/g" "$tmp/autounattend.xml" && rm -f "$tmp/autounattend.xml.bak"
  if command -v genisoimage >/dev/null; then ISO=genisoimage; else ISO=xorriso; fi
  if [ "$ISO" = genisoimage ]; then
    genisoimage -J -R -V X360AUTOUNATTEND -o /tmp/x360-answer.iso "$tmp"
  else
    xorriso -as mkisofs -J -R -V X360AUTOUNATTEND -o /tmp/x360-answer.iso "$tmp"
  fi
  "${PVE_SCP[@]}" /tmp/x360-answer.iso "$PVE_USER@$PVE_HOST:/var/lib/vz/template/iso/x360-answer.iso"
  rm -rf "$tmp" /tmp/x360-answer.iso
}

software() {
  local ip; ip="$(guest_ip)"; [ -z "$ip" ] && { echo "guest IP not found (is Windows up + SSH on?)"; exit 1; }
  log "SOFTWARE install on guest $ip (Xenia + Sunshine + Moonlight Web)"
  local GSSH=(sshpass -p "$GUEST_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$GUEST_USER@$ip")
  local GSCP=(sshpass -p "$GUEST_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
  "${GSSH[@]}" "New-Item -ItemType Directory -Force -Path C:\\X360Arena\\deploy,C:\\X360Arena\\config\\games | Out-Null"
  "${GSCP[@]}" "$REPO_ROOT"/deploy/*.ps1 "$GUEST_USER@$ip:C:/X360Arena/deploy/"
  "${GSCP[@]}" "$REPO_ROOT"/config/games/*.toml "$GUEST_USER@$ip:C:/X360Arena/config/games/"
  # Execution policy is Restricted by default; guest-setup self-sets Bypass but invoke explicitly too.
  "${GSSH[@]}" "powershell -ExecutionPolicy Bypass -File C:\\X360Arena\\deploy\\guest-setup.ps1"
  log "Stream: http://$ip:8080  (Sunshine UI: https://$ip:47990)"
}

gpu() {
  log "GPU bind via control.sh xbox-on (powers off VM $VIDEO_VMID) + NVIDIA driver"
  VMID="$VMID" "$SCRIPT_DIR/control.sh" --yes xbox-on || true
  # wait for guest SSH back, then install the driver (which also flips Sunshine to NVENC)
  local ip; for _ in $(seq 1 40); do ip="$(guest_ip)"; [ -n "$ip" ] && break; sleep 8; done
  [ -z "$ip" ] && { echo "guest IP not found after GPU bind"; exit 1; }
  local GSSH=(sshpass -p "$GUEST_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$GUEST_USER@$ip")
  "${GSSH[@]}" "powershell -ExecutionPolicy Bypass -File C:\\X360Arena\\deploy\\install-nvidia.ps1"
  log "GPU + NVENC ready. nvidia-smi above should list the RTX 3090 Ti."
}

status() {
  "${PVE_SSH[@]}" "qm status $VMID; qm config $VMID | grep -i hostpci || echo 'GPU: not bound'"
  local ip; ip="$(guest_ip)"; echo "guest IP: ${ip:-unknown}"
  [ -n "$ip" ] && curl -s -o /dev/null -w "stream :8080 -> HTTP %{http_code}\n" --max-time 8 "http://$ip:8080" || true
}

case "${1:-all}" in
  provision) provision ;;
  software)  software ;;
  gpu)       gpu ;;
  status)    status ;;
  all)       provision; log "Waiting for Windows install + SSH (can take ~20 min)..."
             for _ in $(seq 1 150); do [ -n "$(guest_ip)" ] && break; sleep 12; done
             software; gpu; status ;;
  *) echo "usage: $0 {provision|software|gpu|all|status}"; exit 2 ;;
esac
