# Xbox 360 Arena — Operator Setup Guide

How to operate the deployed system. For a from-scratch rebuild use `deploy/setup.sh`
(see `README.md`); for playing games see `docs/PLAYING.md`; for the full verdict/inventory
see `docs/HANDOFF.md`.

## 1. Prerequisites
- **Proxmox host:** `bigbrother` (`192.168.0.25`, root / `<HOST_ROOT_PASSWORD — see deploy/SECRETS.md>`)
- **GPU:** NVIDIA RTX 3090 Ti (`hostpci0 = 0000:2d:00`), shared with VM 100 (ai-video-lab)
- **Client:** any machine with Chrome/Safari on the LAN
- **Optional:** an Xbox/generic controller (passes through via the HTML5 Gamepad API)

## 2. VM specification (as deployed — VM 360 `x360-arena`)
- CPU `host`, 16 cores · RAM 32 GiB · 256 GiB NVMe (scsi0) · q35 · OVMF (UEFI) · vTPM 2.0
- Guest: Windows 11 Pro 25H2 (build 26200)
- **GPU passthrough:** `hostpci0: 0000:2d:00,pcie=1` — **compute mode, NO `x-vga`** (matches
  the proven VM 100 config). The emulated VGA is then **disabled inside Windows** so Sunshine
  captures the NVIDIA display for hardware **NVENC**. Consequence: the Proxmox noVNC console
  is black — use SSH or the stream.

## 3. GPU contention — the 3090 Ti is exclusive
VM 360 (gaming) and VM 100 (ai-video-lab) **cannot both hold the GPU.** Use `deploy/control.sh`
(runs on the host, or `ssh root@192.168.0.25`):
- `control.sh xbox-on`  → stops VM 100, attaches the GPU to VM 360, starts it (`--yes` to skip the confirm)
- `control.sh xbox-off` → stops VM 360, detaches the GPU, restarts VM 100 (your video-lab)
- `control.sh status`   → shows which VM holds the GPU

> Current state: GPU bound to VM 360; **VM 100 is OFF.** Run `control.sh xbox-off` when done gaming.

## 4. Launch the arena
If VM 360 is already running, skip to §5. Otherwise:
```bash
ssh root@192.168.0.25            # bigbrother
deploy/control.sh --yes xbox-on  # frees the GPU from VM 100, boots VM 360 with it
```
On boot, these auto-start: OpenSSH (`sshd`), `SunshineService`, and the Moonlight web-server
(Scheduled Task `X360Arena-MoonlightWebStream`). Guest IP is `192.168.3.202` (DHCP, MAC
`BC:24:11:E6:B2:4A`).

## 5. Stream access
- **Browser stream:** `http://192.168.3.202:8080` — login `arena` / `<ARENA_PASSWORD — see deploy/SECRETS.md>`
- **Sunshine admin:** `https://192.168.3.202:47990` — same login
- **Guest SSH/RDP:** `192.168.3.202` — `arena` / `<ARENA_PASSWORD — see deploy/SECRETS.md>`

Connect → launch **Desktop** (or a game app) → see `docs/PLAYING.md` to launch + control games.
Pairing (if needed): Moonlight Web shows a PIN; submit it in Sunshine (already paired once).

## 6. Adding game ROMs (user-supplied)
ROMs are **not** bundled (copyright). Copy a legally-owned dump to the guest:
```bash
scp yourgame.iso arena@192.168.3.202:C:/X360Arena/roms/
```
Then open it in **Xenia Manager** (or a `xenia_canary.exe "path"` shortcut). Per-game flags
are in `config/games/`. Some titles (e.g. Minecraft disc) need a **Title Update** — see
`docs/PLAYING.md` §3.

## 7. Troubleshooting
- **Stream loads but no video** → WebRTC media ports; ensure firewall allows `web-server.exe` +
  `streamer.exe` and UDP 40000–40010, and the Moonlight config has `webrtc.port_range` +
  `nat_1to1` host `192.168.3.202` (already configured).
- **Clicks/keys do nothing in a game** → games are controller-driven and `keyboard_mode` must be
  `1`. Keyboard map: Enter=A, Backspace=B, arrows=D-pad, WASD=move (see `docs/PLAYING.md` §4).
- **Game wedges (~30 MB RAM, no window)** → launched over SSH/Task; launch from the live desktop.
- **Stutter / sub-60 fps** → the Xeon 8173M is single-thread-weak (Xenia is CPU-bound); let
  shaders cache, expect limits on demanding titles.
- **VM won't boot / GPU error** → make sure VM 100 is fully off (`control.sh status`); if the
  PCIe device is stuck, reboot `bigbrother`.
