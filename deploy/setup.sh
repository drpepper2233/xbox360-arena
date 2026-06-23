#!/bin/bash
set -euo pipefail

# Xbox 360 Arena — Operator Entrypoint
# Provisions a Windows 11 VM on Proxmox with GPU passthrough,
# installs the emulator stack (Xenia Canary + Sunshine), configures games,
# and validates streaming to Chrome.
#
# Flow: provision VM → install Windows → bind GPU → run guest-setup.ps1 → stream
# This script documents the end-to-end contract; steps marked TODO are owned by other layers.

set -x  # verbose

# Layer-specific entry points:
# - VM provision + Windows install → Layer VM-1 (Sentinel)
# - GPU binding → Layer VM-2 (Sentinel)
# - Guest automation (PowerShell + Xenia config) → Layer BUILD-1 (Codex)
# - Documentation + handoff → Layer DOCS (Scribe)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${REPO_ROOT}/config"
DEPLOY_DIR="${REPO_ROOT}/deploy"

echo "=== Xbox 360 Arena Setup ==="
echo "Repo root: $REPO_ROOT"
echo "Config dir: $CONFIG_DIR"

# Step 1: Provision VM on Proxmox (Layer VM-1)
# TODO: Layer VM-1 (Sentinel) — create Windows 11 VM on bigbrother with:
#   - VMID: 360 (or next free, per PLAN L3)
#   - Name: x360-arena
#   - q35 + OVMF (UEFI) + vTPM
#   - CPU: 16 cores, RAM: 32 GiB, NVMe: 256 GiB
#   - Install Windows 11 + NVIDIA Game Ready driver
#   - Report VM ready and accessible via RDP

echo "Step 1: TODO — Provision Windows 11 VM (Layer VM-1, Sentinel)"

# Step 2: Bind GPU passthrough (Layer VM-2)
# TODO: Layer VM-2 (Sentinel) — bind RTX 3090 Ti to the VM:
#   - Resolve GPU PCI address from existing VM 100 (ai-video-lab)
#   - Power off VM 100
#   - Add hostpci0 = RTX 3090 Ti (x-vga=1, all functions) to VM 360
#   - Boot VM 360, verify GPU appears in Device Manager

echo "Step 2: TODO — Bind GPU passthrough (Layer VM-2, Sentinel)"

# Step 3: Copy per-game configs to VM
# TODO: Transfer config/games/*.toml files to VM (/path/to/xenia/config/)
echo "Step 3: TODO — Copy per-game configs from config/games/ to guest"

# Step 4: Run guest automation (Layer BUILD-1)
# TODO: Layer BUILD-1 (Codex) — execute guest-setup.ps1 on Windows:
#   - Install Xenia Canary (D3D12 backend) + Xenia Manager
#   - Install Sunshine (NVENC streaming)
#   - Configure per-game settings from config/games/*.toml
#   - Enable Sunshine service
#   - Output the stream URL (e.g., https://VM-IP:8443)

echo "Step 4: TODO — Run guest-setup.ps1 on Windows VM (Layer BUILD-1, Codex)"

# Step 5: Validate streaming
# TODO: Test streaming to Chrome from another host:
#   - Open Moonlight-web (or fallback client) at the URL from Step 4
#   - Verify video feed (low-latency H.264/HEVC via NVENC)
#   - Test gamepad input (HTML5 Gamepad API)
#   - Verify Sunshine logs show active stream

echo "Step 5: TODO — Validate streaming to Chrome"

# Step 6: Verify game compatibility (Layer VERIFY)
# TODO: Layer VERIFY (Quill) — test at least the 10 Playable titles:
#   - Minecraft (required; must run if ROM supplied)
#   - Red Dead Redemption, Skate 3, Castle Crashers, Fable II, Halo 3,
#     Gears of War, Sonic Generations, Halo: Reach, Banjo-Kazooie: Nuts & Bolts
#   - For each title: boot, verify D3D12 rendering, confirm gamepad responds

echo "Step 6: TODO — Verify game compatibility (Layer VERIFY, Quill)"

# Step 7: Documentation & handoff (Layer DOCS)
# TODO: Layer DOCS (Scribe) — produce docs/SETUP.md and L18 handoff verdict:
#   - Record exact provisioning steps, IP/credentials, stream URL
#   - Verify setup is reproducible from this script + docs
#   - Produce layer18-handoff-YYYY-MM-DD-HHMM.md (READY / READY WITH RISKS / NOT READY)

echo "Step 7: TODO — Documentation & handoff (Layer DOCS, Scribe)"

echo "=== Setup contract complete ==="
echo "All steps marked TODO are owned by other layers (per PLAN L5)."
echo "When all layers complete, the full pipeline is: provision VM → install Windows → bind GPU →"
echo "run guest-setup.ps1 (configures games from config/games/) → stream to Chrome → verify games."
