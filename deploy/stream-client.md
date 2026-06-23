# Browser Stream Client

Primary client: **Moonlight Web Stream** (`MrCreativ3001/moonlight-web-stream`), not `moonlight-chrome`.

Why: the old Moonlight Chrome app depended on Chrome/NaCl-era packaging and is not the browser path to build against in 2026. Moonlight Web Stream is a current WebRTC browser bridge for Sunshine; latest verified release during authoring was `v2.10.0`, published May 29, 2026, with a Windows asset named `moonlight-web-x86_64-pc-windows-gnu.zip`.

## Host Setup

Run `deploy/guest-setup.ps1` inside the Windows 11 guest as Administrator after the VM exists and NVIDIA drivers are installed. The script installs:

- Xenia Canary from the current `xenia-canary/xenia-canary` Windows release asset.
- Xenia Manager from the current `xenia-manager/xenia-manager` release asset.
- Sunshine from the current LizardByte Windows AMD64 MSI.
- Moonlight Web Stream from the current Windows release asset.

Installed paths:

- `C:\X360Arena\XeniaCanary`
- `C:\X360Arena\XeniaManager`
- `C:\X360Arena\MoonlightWeb` (`web-server.exe` is under the extracted `package` directory)
- Sunshine default config path: `%ProgramFiles%\Sunshine\config`

The script writes Moonlight Web Stream config to the `server\config.json` path beside `web-server.exe`, currently `C:\X360Arena\MoonlightWeb\package\server\config.json`:

```json
{
  "web_server": {
    "bind_address": "0.0.0.0:8080"
  },
  "webrtc": {
    "port_range": {
      "min": 40000,
      "max": 40010
    }
  }
}
```

Firewall opened by the script:

- Moonlight Web: TCP `8080`, UDP `40000-40010`
- Sunshine: TCP `47984,47989,47990,48010`, UDP `47998-48000,48010`

Sunshine URLs after setup:

- Browser client: `http://<guest-ip>:8080`
- Sunshine UI and PIN pairing: `https://<guest-ip>:47990`

## Chrome Connection

1. Open `https://<guest-ip>:47990` and create the first Sunshine admin account.
2. In Sunshine, confirm `Desktop`, `Xenia Manager`, and `Xenia Canary` appear in Applications.
3. Install ViGEmBus from Sunshine Web UI > Troubleshooting if Sunshine reports no virtual gamepad driver, then reboot the guest.
4. Open `http://<guest-ip>:8080` in Chrome.
5. Create the first Moonlight Web admin user.
6. Add a PC with address `localhost` and the default Sunshine port.
7. Pair from Moonlight Web, then enter the PIN in Sunshine.
8. Launch `Desktop` first for smoke test, then `Xenia Manager` or `Xenia Canary`.

## Gamepad Support

Sunshine on Windows needs ViGEmBus for virtual gamepad injection. Moonlight Web Stream also documents controller capture as a browser secure-context feature. For final gamepad acceptance in Chrome, use one of these:

- Serve Moonlight Web Stream through HTTPS on the LAN and trust the certificate in Chrome.
- Run the Moonlight Web Stream server on the Chrome client machine and access it as `localhost`, then add the Sunshine host by guest IP.
- For a short lab-only check, configure Chrome to treat `http://<guest-ip>:8080` as a secure origin, then remove that override after testing.

Acceptance check: Chrome sees the local controller, Moonlight Web Stream forwards it, Sunshine logs a connected virtual gamepad, and Xenia receives Xbox 360 controller input.

## Per-Game Config Contract

`guest-setup.ps1` consumes future repo files at `config/games/*.toml`. Each file must include:

```toml
title_id = "584111F7"
license_mask = 1
apu = "sdl"
max_queued_frames = 3
```

If a file contains a `[xenia]` section, only that section is copied into Xenia's per-title config. Otherwise, top-level metadata keys such as `title_id`, `title`, `slug`, `tier`, and `notes` are stripped, and the remaining flags are written to:

```text
C:\X360Arena\XeniaCanary\config\<TITLE_ID>.config.toml
```

The global Xenia Canary config is written to use D3D12:

```toml
gpu = "d3d12"
apu = "sdl"
apply_patches = true
max_queued_frames = 3
mount_cache = true
```

## Fallback

Fallback is Neko only for browser-based remote desktop if Moonlight Web Stream cannot pass the network, browser secure-context, or controller requirements. Neko is not the primary game-streaming path because it is not Sunshine/Moonlight-compatible, is not tuned for NVENC game latency, and gamepad behavior must be proven separately.

## Sources Checked

- Moonlight Web Stream README and config: https://github.com/MrCreativ3001/moonlight-web-stream
- Moonlight Web Stream latest release: https://github.com/MrCreativ3001/moonlight-web-stream/releases/tag/v2.10.0
- Sunshine Windows install and service behavior: https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html
- Sunshine config and app examples: https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2configuration.html
- Xenia Canary options/per-game config behavior: https://github.com/xenia-canary/xenia-canary/wiki/Options
