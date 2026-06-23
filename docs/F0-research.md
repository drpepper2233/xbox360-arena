# Xbox 360 Arena — F0 Research Report

## 1. EMULATOR
The definitive Xbox 360 emulator in 2026 is **Xenia Canary**. 

### Xenia Canary vs. Xenia Master
*   **Xenia Master** acts as the stable baseline. However, it is updated very infrequently and lacks critical modern optimizations, rendering fixes, and features required to run a majority of the Xbox 360 library.
*   **Xenia Canary** is the active experimental fork. It is the community standard because it integrates performance patches (unlocked 60/120 FPS, post-processing removal, aspect ratio fixes), modern shader compilation enhancements, and title-specific rendering hacks.
*   **Xenia Manager** is the recommended frontend manager to manage game titles, automate configuration files, and pull down compatibility patches.

### Host Platform Compatibility
*   **Linux Viability:** Xenia does not have a stable native Linux build. However, running the Windows build of Xenia Canary on Linux via translation layers like **Proton** (leveraged through EmuDeck or Lutris) or **Wine** is highly viable and performs near-natively.
*   **GPU API Backend:** The emulator relies heavily on **DirectX 12 (D3D12)**. D3D12 translation (using `vkd3d-proton` on Linux/Proton) is the primary rendering path, offering the highest compatibility. The Vulkan backend exists but is considered an experimental troubleshooting fallback that suffers from visual bugs and missing render passes.
*   **RTX 3090 Ti Support:** Fully compatible. The RTX 3090 Ti supports Rasterizer Ordered Views (ROV) and DirectX 12 Feature Level 12_2, both of which are strictly required by Xenia to prevent severe graphical corruption and vertex explosions.

**VERDICT: Xenia Canary (configured to use the D3D12 graphics backend and managed via Xenia Manager) is the optimal emulator choice.**

---

## 2. GUEST OS + GPU
To host Xenia Canary on the "bigbrother" Proxmox host, a **Windows 11 Guest VM with exclusive PCI Passthrough of the RTX 3090 Ti** is recommended.

### Windows 11 vs. Linux Guest
*   Windows 11 allows Xenia to interface directly with the DirectX 12 API and native NVIDIA Windows graphics drivers, bypassing the double-translation layer (Xenia -> Windows D3D12 -> Proton/vkd3d -> Linux Vulkan) that a Linux guest would introduce. It also simplifies Sunshine gamepad/driver setups.

### Performance Requirements & Bottlenecks
*   Xenia JIT emulates the PowerPC Xenon CPU, which demands high single-thread CPU performance. It requires AVX2 (which the host Xeon 8173M supports).
*   **CPU Bottleneck:** The Intel Xeon 8173M (2.0 GHz base, 3.5 GHz max turbo) has relatively low single-thread performance compared to modern consumer desktop CPUs. Consequently, JIT translation will be a major performance bottleneck, leading to stuttering during runtime shader compilation and difficulty maintaining stable 60 FPS in demanding games.
*   **GPU Bottleneck:** None. The RTX 3090 Ti is overkill for Xenia's GPU translation needs, assuming ROV is enabled.
*   **Storage:** Fast NVMe storage is required to cache shaders rapidly and eliminate asset loading freezes.

### GPU Contention (VM 100)
*   PCI passthrough on Proxmox VE is strictly **exclusive** for consumer NVIDIA GPUs. The RTX 3090 Ti cannot be split or shared via vGPU/GRID virtualization (since `vgpu_unlock` does not support Ampere/RTX 30-series architectures). 
*   **Contention Reality:** The existing VM 100 must be powered off before booting the Xbox 360 Arena VM, or the GPU must be fully de-allocated from VM 100.

**VERDICT: Windows 11 Guest VM with exclusive RTX 3090 Ti PCI Passthrough, noting that VM 100 must be shut down during use and the Xeon 8173M CPU's single-thread clock speed will bottleneck emulation framerates.**

---

## 3. BROWSER STREAMING
To play the emulator directly within a Chrome browser window with minimal latency and full controller input:

### Option Analysis
1.  **Sunshine + Moonlight-web (WebRTC/WASM) [RECOMMENDED]:** Sunshine runs on the Windows guest, encoding video using NVENC (low-latency H.264/HEVC on the RTX 3090 Ti). The browser accesses the host using the `Moonlight-web` client, which uses WebAssembly (WASM) and WebGL to decode video streams and routes inputs directly through Chrome's Gamepad API.
2.  **Selkies-GStreamer:** Designed for containerized Linux desktops streaming WebRTC. Highly complex to install and configure for a Windows VM guest.
3.  **Neko:** A virtual browser sharing container. Uses WebRTC but is built for administrative desktop sharing/co-browsing; it lacks the low-latency game-focused audio/video optimization and input routing required for fast gaming.
4.  **noVNC:** A basic VNC-to-WebSocket bridge. Lacks hardware encoding, has high visual latency, lacks audio transmission, and has no controller support. Unusable for gaming.
5.  **Parsec:** Excellent latency, but its browser/Chrome client has been deprecated, requiring the native desktop client app for optimal function. Lacks self-hosted offline flexibility.

**VERDICT: Sunshine (Host) with Moonlight-web (Client) is the PRIMARY recommendation due to hardware-accelerated WebRTC streaming and native HTML5 Gamepad API translation. Neko is the FALLBACK solution for simple browser sharing at the cost of latency and input precision.**

---

## 4. GAME COMPATIBILITY
Current emulation capability on Xenia Canary for the requested titles:

*   **Minecraft: Xbox 360 Edition (Title ID: `584111F7`)**
    *   *Compatibility Tier:* **Playable**
    *   *Status:* Runs near-flawlessly at stable 60 FPS. 
    *   *Required Flags:* Set `license_mask = 1` in `xenia-canary.config.toml` to bypass the trial mode. Set `apu = "sdl"` and `max_queued_frames = 3` to resolve minor audio stuttering.
*   **Call of Duty: Black Ops (Title ID: `41560855`)**
    *   *Compatibility Tier:* **Runs** (Gameplay)
    *   *Status:* Boots, menus are navigable, and gameplay loads. However, there is persistent shader stutter, lighting artifacts common to the IW Engine in Xenia, and potential hangs during mission transitions.
    *   *Required Flags:* Enable `apply_patches = true` and ensure the Black Ops performance patch is active. Set `clear_memory_page_table = true` to mitigate heap crashes.
*   **Call of Duty: Black Ops II (Title ID: `415608C3`)**
    *   *Compatibility Tier:* **Broken** (Loads)
    *   *Status:* Boots to the initial loading screen and menus but consistently crashes or hangs on a "cyan screen" when attempting to load Campaign or Multiplayer matches.
    *   *Required Flags:* Requires experimental community patches to boot past menus, but gameplay is unstable and unplayable.

**VERDICT: Minecraft is Playable (with license unlock); COD Black Ops 1 Runs with visual bugs; COD Black Ops 2 is Broken.**

---

## 5. THE 10 GAMES
A curated demo set of 10 titles including the 3 required games, prioritized by Xenia Canary compatibility:

1.  **Minecraft: Xbox 360 Edition** (Title ID: `584111F7`) — **Playable**. Config: `license_mask = 1`, `apu = "sdl"`.
2.  **Call of Duty: Black Ops** (Title ID: `41560855`) — **Runs**. Config: `apply_patches = true`, `clear_memory_page_table = true`.
3.  **Call of Duty: Black Ops II** (Title ID: `415608C3`) — **Broken**. Config: Requires experimental patch.toml to bypass boot hangs.
4.  **Red Dead Redemption** (Title ID: `5454082B`) — **Playable**. Config: `mount_cache = true` (enables local asset caching to prevent random freezes), `clear_memory_page_table = true`, and apply the 60 FPS performance patch.
5.  **Skate 3** (Title ID: `454108E6`) — **Playable**. Config: `vsync = false` in Xenia (forces the use of external frame caps to prevent physics glitches and frame stutters).
6.  **Castle Crashers** (Title ID: `584108A7`) — **Playable**. Config: `license_mask = 1` (to unlock full XBLA version). Runs flawlessly at 60 FPS.
7.  **Fable II** (Title ID: `4D5307F1`) — **Playable**. Config: `readback_resolve = "full"` under the GPU section to fix the infamous black textures on characters and the dog.
8.  **Halo 3** (Title ID: `4D5307E6`) — **Playable**. Config: `apply_patches = true` and ensure the Halo 3 HDR/lighting patch is enabled to resolve black shaders.
9.  **Gears of War** (Title ID: `4D5307D5`) — **Playable**. Config: Default settings are stable; 60 FPS patch recommended.
10. **Sonic Generations** (Title ID: `53450849`) — **Playable**. Config: Native settings run reliably at stable framerates.

**VERDICT: The 10-game set includes 8 Playable titles, 1 Runs title, and 1 Broken title, proving the viability of Xenia Canary for main exclusives while highlighting engine-specific compatibility gaps (IW engine on Black Ops II).**

---

## RECOMMENDED ARCHITECTURE
The recommended architecture consists of a Windows 11 guest VM running on Proxmox VE with exclusive PCI passthrough of the RTX 3090 Ti. On the Windows host, the latest experimental build of Xenia Canary is installed and configured using the DirectX 12 rendering backend, managed via Xenia Manager for automated game organization and patch ingestion. Sunshine is installed as a system service on the guest VM to leverage NVENC (NVIDIA NVENC H.264/HEVC) hardware encoding on the GPU, while game controller and keyboard inputs are captured client-side using a browser-based Moonlight-web client hosted on a local static web server. To avoid resource contention, VM 100 is shut down prior to launch, and game configurations utilize the `license_mask = 1` flag for XBLA arcade titles and per-game patch `.toml` configurations to resolve individual shader, lighting, and texture resolution constraints.

---

## SOURCES
1.  Xenia Emulator Project & Compatibility Database: [https://github.com/xenia-canary/game-compatibility](https://github.com/xenia-canary/game-compatibility)
2.  Xenia Canary Game Patches Repository: [https://github.com/xenia-canary/game-patches](https://github.com/xenia-canary/game-patches)
3.  Xenia Manager Main Project Site: [https://xenia-manager.github.io/](https://xenia-manager.github.io/)
4.  LizardByte Sunshine Host Streaming Documentation: [https://github.com/LizardByte/Sunshine](https://github.com/LizardByte/Sunshine)
5.  Moonlight Web client interface: [https://github.com/moonlight-stream/moonlight-chrome](https://github.com/moonlight-stream/moonlight-chrome)
6.  Proxmox VE PCI Passthrough Reference: [https://pve.proxmox.com/wiki/PCI_Passthrough](https://pve.proxmox.com/wiki/PCI_Passthrough)
