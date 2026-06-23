# Xbox 360 Arena — Layer 18 Handoff Verification

## 1. Handoff Verdict
- **Status:** ✅ **READY WITH RISKS**
- **Assessed On:** 2026-06-23
- **Assessed By:** Elder (Opus) — built and verified live, end to end
- **Summary:** The full pipeline works and is GPU-accelerated — Xbox 360 emulation
  (Xenia Canary) on a Windows 11 VM, captured + NVENC-encoded by Sunshine, streamed to
  a web browser via Moonlight Web. **Verified end-to-end: Minecraft: Xbox 360 Edition
  boots into the game in the browser** (title `584111F7`, via TU75 — see `docs/PLAYING.md`).
  Outstanding items are an optional gamepad driver (ViGEmBus) and the documented risks in §7.
- **How to play:** see **`docs/PLAYING.md`** — connect, launch from the desktop, the Minecraft
  Title-Update fix, and the keyboard/controller mapping.

---

## 2. Access URLs & Credentials
| What | Address | Login |
|------|---------|-------|
| **Browser stream (open in Chrome/Safari)** | `http://192.168.3.202:8080` | `arena` / `REDACTED` (first login created admin) |
| **Sunshine admin UI** | `https://192.168.3.202:47990` | `arena` / `REDACTED` |
| **Windows guest (SSH / RDP)** | `192.168.3.202:22` / `:3389` | `arena` / `REDACTED` |
| **Proxmox host (bigbrother)** | `https://192.168.0.25:8006` · `ssh root@192.168.0.25` | `root` / `REDACTED` (+ M1-SLAB key) |

> Pairing: Moonlight Web → add host → enter the PIN it shows into Sunshine. Already paired
> once on 2026-06-23 (PIN 1116, `{"status":true}`). Re-pair anytime via the Sunshine UI.

---

## 3. System Inventory (verified)
| Component | Spec / Version | Verified |
|-----------|----------------|----------|
| Host | Proxmox VE 9.1.1, kernel 6.17.2-1-pve, host `bigbrother` 192.168.0.25 (Xeon 8173M 112t / 125 GiB) | ✅ |
| VM | VMID **360** `x360-arena`: q35 (pc-q35-10.1), OVMF, vTPM 2.0, 16 cores, 32 GiB RAM, 256 GiB NVMe (scsi0), net virtio `BC:24:11:E6:B2:4A` | ✅ `qm config 360` |
| GPU passthrough | RTX 3090 Ti `hostpci0: 0000:2d:00,pcie=1` (compute mode, no x-vga) | ✅ |
| Guest OS | Windows 11 Pro 10.0.26200 (25H2), unattended install | ✅ |
| NVIDIA driver | 610.62 (DCH), `nvidia-smi` OK, 24564 MiB | ✅ |
| Emulator | Xenia Canary + Xenia Manager → `C:\X360Arena\XeniaCanary`, `...\XeniaManager` | ✅ |
| Stream host | Sunshine (service `SunshineService`) — **hevc_nvenc @ 1920×1080 60 Hz** | ✅ log confirms |
| Browser client | Moonlight Web (`C:\X360Arena\MoonlightWeb\package\web-server.exe`) on `:8080` | ✅ HTTP 200 from Mac |
| Game configs | 10 Playable + BO1/BO2 best-effort → `C:\X360Arena\config\games\*.toml` | ✅ 12 files |

---

## 4. Architecture
```
Chrome/Safari ──HTTP/WebRTC──▶ Moonlight Web (:8080, web-server.exe)
                                      │  pairs with
                                      ▼
                               Sunshine (:47990, NVENC capture+encode)
                                      │ captures the
                                      ▼
                          RTX 3090 Ti display @ 1080p60  ◀── Xenia Canary renders games (D3D12)
                                      ▲
                          Windows 11 VM 360 on Proxmox host bigbrother
```
The emulated VGA is **disabled** so Sunshine captures the 3090 Ti's output (required for NVENC).

---

## 5. Operation — Start / Stop / GPU on demand
The RTX 3090 Ti is **exclusive**: VM 360 (gaming) and VM 100 (ai-video-lab) cannot both
hold it. Switch with `deploy/control.sh` (runs on the host):
- `control.sh xbox-on`  → stops VM 100, attaches GPU to 360, starts 360 (asks before powering off the video-lab; `--yes` to skip)
- `control.sh xbox-off` → stops 360, detaches GPU, restarts VM 100 (video-lab)
- `control.sh status`   → shows which VM holds the GPU

**Current state:** GPU is bound to VM 360; **VM 100 (ai-video-lab) is powered OFF.** Run
`control.sh xbox-off` when you're done gaming to restore the video-lab.

**Auto-start on boot:** `sshd` (service), `SunshineService` (service), and the Moonlight
web-server (Scheduled Task `X360-MoonlightWeb`, AtLogOn) all come back automatically.

---

## 6. ROMs (your part)
Copy a legally-owned dump (`.iso` / `.god` / extracted `.xex`) to the VM, e.g.:
`scp game.iso arena@192.168.3.202:C:/X360Arena/roms/`, then open it in **Xenia Manager**
(it applies the per-game flags in `config/games/`). Required games: Minecraft (Playable),
plus 9 more Playable titles; BO1 runs with issues, BO2 is broken (see F0-research.md §4–5).

---

## 7. Known Risks
1. **CPU bottleneck.** Xeon 8173M single-thread is weak; Xenia is single-thread heavy →
   stutter / sub-60 fps in demanding titles. GPU is overkill; the CPU is the limit.
2. **GPU contention.** Gaming requires VM 100 (ai-video-lab) **off**. Mutually exclusive.
3. **No ROMs shipped** (copyright) — emulator + configs are ready; games unverified until you add files.
4. **BO2 broken / BO1 partial** on Xenia — substituted with Playable titles in the counted 10.
5. **Proxmox console is black** (emulated VGA disabled for NVENC) — use SSH / the stream, not the noVNC console.
6. **Guest can't reach Windows Update FoD** — all installs were mirrored from the host LAN (`:8099`). Keep that in mind for future driver/feature installs.

---

## 8. Build Reproducibility — fixes applied live (fold back into scripts)
These were fixed by hand on the running VM; **fold into the repo scripts for a clean rebuild:**
1. `autounattend.xml` FirstLogonCommands must run `bootstrap.ps1` from the **answer-ISO CD**, not `C:\` (chicken-and-egg — partial fix committed, verify on next build).
2. OpenSSH: WU FoD hangs (no internet to MS) → install from the **Win32-OpenSSH GitHub zip mirrored on the host LAN**; the auto-login shell is **non-elevated**, so it must self-elevate (UAC).
3. `guest-setup.ps1`: removed `Set-StrictMode` (crashed) + fixed `Get-PrimaryIPv4` (committed); firewall rule bug (empty port) — added rules manually, fix in script.
4. Game configs needed `title_id` + `[xenia]` flags (Knight's stubs were empty) — **fixed & committed**.
5. Moonlight `config.json` written with a UTF-8 BOM + partial schema (Rust serde rejected) → use clean UTF-8 `{}` (defaults). web-server must run via **Scheduled Task** (SSH-spawned processes die on disconnect).
6. NVENC: disable the emulated VGA (`Disable-PnpDevice` Microsoft Basic Display) so Sunshine captures the 3090 Ti.

Full forensic detail is in the session memory neurons (search `xbox360-arena`).
