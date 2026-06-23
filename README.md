# xbox360-arena

Xbox 360 emulation (Xenia Canary) in a Windows 11 Proxmox VM with RTX 3090 Ti passthrough,
streamed to a web browser via Sunshine (NVENC) + Moonlight Web. Built and verified live on
**bigbrother** (Proxmox 192.168.0.25) on 2026-06-23.

**Status: ✅ READY WITH RISKS** — full pipeline works and is GPU-accelerated. See
[`docs/HANDOFF.md`](docs/HANDOFF.md) for the verdict, access URLs, credentials, and risks.

## Quick access (current deployment)
| What | URL | Login |
|------|-----|-------|
| Browser stream | `http://192.168.3.202:8080` | `arena` / `AdVictoriam360!` |
| Sunshine UI | `https://192.168.3.202:47990` | `arena` / `AdVictoriam360!` |
| Guest SSH/RDP | `192.168.3.202` | `arena` / `AdVictoriam360!` |

> The RTX 3090 Ti is shared with VM 100 (ai-video-lab) — they can't run at once.
> `deploy/control.sh xbox-off` returns the GPU to the video-lab; `xbox-on` takes it back.

## Rebuild from scratch (single entrypoint)
Requires `ssh`, `scp`, `sshpass`, and `genisoimage`/`xorriso` locally; the Windows 11 and
virtio ISOs must already be on the Proxmox host.

```bash
deploy/setup.sh all          # provision VM → unattended Windows → guest stack → GPU + NVENC
# or step by step:
deploy/setup.sh provision    # create VM 360 + answer ISO + start Windows install
deploy/setup.sh software     # push payload + run guest-setup.ps1 (Xenia + Sunshine + Moonlight)
deploy/setup.sh gpu          # control.sh xbox-on + install NVIDIA driver + enable NVENC
deploy/setup.sh status       # VM + stream health
```

## What's in here
- `deploy/setup.sh` — host orchestrator (the operator entrypoint)
- `deploy/control.sh` — on-demand GPU switcher (`xbox-on` / `xbox-off` / `status`)
- `deploy/autounattend.xml` + `deploy/bootstrap.ps1` — hands-free Windows install + first-logon
  remote-access bootstrap (self-elevates, installs OpenSSH from the GitHub zip, enables RDP)
- `deploy/guest-setup.ps1` — in-guest stack: Xenia Canary + Xenia Manager + Sunshine +
  Moonlight Web + per-game configs + firewall + NVENC enablement
- `deploy/install-nvidia.ps1` — silent NVIDIA driver install + NVENC switch
- `config/games/*.toml` — 10 Playable titles + BO1/BO2 (best-effort); `title_id` + `[xenia]` flags
- `docs/` — `F0-research.md` (emulator/streaming/compat research), `PLAN.md` (L1–L8),
  `SETUP.md` (operator guide), `HANDOFF.md` (Layer 18 verdict + reproducibility notes)

## Hard-won gotchas (already fixed in the scripts; read before changing them)
1. The guest **cannot reach Windows Update FoD** — `Add-WindowsCapability` hangs forever. All
   downloads (OpenSSH, NVIDIA driver) come from GitHub / NVIDIA CDN or a host LAN mirror.
2. The auto-login account is admin but its shell is **non-elevated** — scripts self-elevate via UAC.
3. PowerShell **execution policy is Restricted** by default — scripts set Bypass.
4. Moonlight `config.json` must be **clean UTF-8 (no BOM)**; a partial `web_server` object is
   rejected by its Rust parser — use `{}` (defaults).
5. Processes spawned over SSH die on disconnect — the Moonlight web-server runs as a **Scheduled Task**.
6. For **NVENC**, the emulated VGA must be disabled so Sunshine captures the NVIDIA display.
7. The Proxmox **noVNC console is black** by design (emulated VGA disabled) — use SSH / the stream.

## Games (ROMs are user-supplied — copyright)
Copy a dump to `C:\X360Arena\roms\` on the guest and open it in **Xenia Manager**; the per-game
flags in `config/games/` apply automatically. Black Ops 2 is broken on Xenia and Black Ops 1 is
partial — the counted 10 are all verified Playable (see `docs/F0-research.md`).
