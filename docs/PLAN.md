# xbox360-arena — MASTER PLAN (Elder, L1–L8)
Session: .forge-session-484703000 · Host: bigbrother (192.168.0.25) · 2026-06-23
Fresh project. NOT a continuation of xenia-cloud.

## L1 — SCOPE (from F1)
Xbox 360 emulator in a VM on bigbrother, streamed to Chrome. 10 working games
incl. Minecraft; BO1/BO2 attempted as best-effort. See F1-wants.txt.

## L2 — ARCHITECTURE (from F0, accepted)
Windows 11 guest VM (Proxmox q35+OVMF) → exclusive RTX 3090 Ti passthrough →
Xenia Canary (D3D12 backend, Xenia Manager) → Sunshine (NVENC) → Moonlight-web in Chrome.
Fallback stream: Neko. Decisions: substitute broken COD with Playable titles; Xbox VM
claims GPU on demand, VM 100 (ai-video-lab) powered off during use.

## L3 — VM TARGET SPEC
- VMID: next free on bigbrother (propose 360). Name: x360-arena.
- q35 + OVMF (UEFI) + vTPM (Win11 req) + cpu=host, 16 cores, 32 GiB RAM, 256 GiB NVMe.
- hostpci0 = RTX 3090 Ti (reuse the exact PCI addr from `qm config 100`'s hostpci line),
  x-vga=1, all functions (GPU+audio). machine=pc-q35, bios=ovmf, efidisk on NVMe.
- Guest: Windows 11, NVIDIA Game Ready driver, RDP/Sunshine enabled.

## L4 — GAME ROSTER (final)
Guaranteed-working set (verify each against Xenia compat DB before claiming):
 1 Minecraft: Xbox 360 Edition (584111F7) — Playable [REQUIRED]
 2 Red Dead Redemption (5454082B) — Playable
 3 Skate 3 (454108E6) — Playable
 4 Castle Crashers (584108A7) — Playable
 5 Fable II (4D5307F1) — Playable
 6 Halo 3 (4D5307E6) — Playable
 7 Gears of War (4D5307D5) — Playable
 8 Sonic Generations (53450849) — Playable
 9 Banjo-Kazooie: Nuts & Bolts (4D5307ED) — Playable [F0b verified; native 1x scale]
10 Viva Piñata (4D5307F2) — Playable [F0b: replaces Halo Reach (only "Runs"); scribble_heap=true]
Best-effort extras (install, do not count toward the 10): COD Black Ops 1 (Runs),
COD Black Ops 2 (Broken — attempt patches, expect failure).
WEB CLIENT (F0b): primary moonlight-web-stream (MrCreativ3001); alt vibeshine/luminalshine (/webrtc).
NOTE: Game ROM/ISO files are the High Elder's to supply (copyright). Emulator+stream
are built independent of ROMs; per-game verification needs the files present.

## L5 — WORK BREAKDOWN → AGENT
- VM-1 (Sentinel/infra): create Win11 VM on bigbrother, UEFI+vTPM, install Windows,
  drivers. Gather GPU PCI addr from VM100. STOP before binding GPU (needs VM100 off).
- VM-2 (Sentinel): bind 3090 Ti passthrough (VM100 off), boot, verify GPU in guest.
- BUILD-1 (Codex): author idempotent in-guest setup (PowerShell) — install Xenia Canary
  + Xenia Manager + Sunshine, write per-game xenia-canary.config.toml from config/games/.
- SCAFFOLD (Knight): repo structure — deploy/, config/games/<title>.toml templates,
  README stubs; one operator entrypoint deploy/setup.sh contract.
- DOCS (Scribe): docs/SETUP.md + handoff skeleton; record exact steps & access URL.

## L6 — INTERFACES
- config/games/<slug>.toml = per-title Xenia flags (license_mask, apu, patches…).
- deploy/setup.sh = single operator entrypoint (provision/verify), per layer-15 rule.
- Stream access contract: Chrome URL + port; gamepad via HTML5 Gamepad API.

## L7 — RISKS
- Xeon 8173M weak single-thread → JIT stutter; can't fix in SW, set expectations.
- moonlight-chrome NaCl client deprecated → Codex must validate a current WASM web
  client (e.g. moonlight-web/WebRTC fork) or fall back to Neko/Selkies.
- GPU contention: binding GPU powers off ai-video-lab (approved).
- ROMs: user-supplied; verification of "game works" gated on files present.

## L8 — DONE-WHEN
1) Win11 VM live on bigbrother with 3090 Ti visible in Device Manager.
2) Xenia Canary launches a title using D3D12 on the GPU.
3) Sunshine stream reachable in Chrome from another machine; video+gamepad work.
4) >=10 Playable titles configured (config present); Minecraft demonstrated playable
   when its ROM is supplied. BO1/BO2 installed as best-effort.
5) deploy/setup.sh reproduces the in-guest setup; docs/handoff verdict written (L18).
