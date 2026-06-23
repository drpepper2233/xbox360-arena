# Xbox 360 Arena — Playing Games

How to actually launch and play, plus every gotcha we hit and solved on 2026-06-23.
Status: **Minecraft: Xbox 360 Edition verified booting into the game** via the browser stream.

---

## 1. Connect to the stream
1. Browser → **`http://192.168.3.202:8080`** (Chrome/Safari) → log in `arena` / `AdVictoriam360!`
2. Connect to the host (paired) → launch **Desktop** (you'll see the live Windows desktop)
3. Make sure the stream has input focus: **click on the video** once, or use the Moonlight
   overlay's **"Keyboard"** / **"Lock Mouse"** buttons (left side of the stream UI).

> Stream tuning already applied: WebRTC media is pinned to **UDP 40000–40010** with
> `nat_1to1` host = `192.168.3.202`, firewall open for `web-server.exe` + `streamer.exe`.
> Without this the stream page loads but the video never connects.

---

## 2. Launch a game — IMPORTANT: do it from the desktop, not SSH
Xenia is a D3D12 GUI app and **only renders in the live interactive desktop session**.
Launching it over SSH or a plain Scheduled Task wedges it at init (no window station).
So: **double-click the shortcut on the streamed desktop**, or it's a Sunshine app.

Desktop shortcuts (on `arena`'s desktop):
- **`1) Play Minecraft`** → Xenia + the Minecraft ISO
- **`2) Minecraft RELAUNCH`** → Xenia with **no ROM** (needed for the Minecraft 2-step, below)
- **`Xenia Manager`** → library UI to add/launch any ROM in `C:\X360Arena\roms\`

Sunshine app launchers (in the Moonlight host list): Desktop, Xenia Manager, Xenia Canary,
Minecraft (Xbox 360).

---

## 3. The Minecraft disc fix (the "Launching new title" loop) — SOLVED
The retail disc ISO boots a loader (title `4D530A81`) that hands off to the real game
(`584111F7`). With no Title Update installed, the handoff loops forever
("Launching new title — please close Xenia and launch it again"). This is a known Xenia
disc bug (`no-disc-install`), not a VM problem.

**Fix applied (already done):**
1. Installed **TU75** (the final Minecraft 360 Title Update, from the Internet Archive,
   STFS `LIVE` package, TitleID `584111F7`, content type `000B0000`) into Xenia's content
   folder: `C:\X360Arena\XeniaCanary\content\584111F7\000B0000\TU75`.
2. Launch sequence that works:
   - Double-click **`1) Play Minecraft`** → disc loads `4D530A81` → "Launching new title" dialog
   - Close Xenia
   - Double-click **`2) Minecraft RELAUNCH`** (no ROM) → Xenia loads the pending title
     `584111F7` **with TU75** → intros → main menu. (Title bar then reads `[584111F7]`.)

To add other Minecraft TUs or any game's TU later: in Xenia, **File → Install Content** →
pick the TU, or drop it in `content\<TitleID>\000B0000\`.

---

## 4. Controls (keyboard) — already configured
Set in `xenia-canary.config.toml`: `keyboard_mode = 1`, `hid = "winkey"`.

| Keyboard | Xbox 360 button |
|----------|-----------------|
| **Enter** | **A** (confirm / OK) |
| **Backspace** | **B** (back) |
| **Arrow keys** | D-pad (menu navigation) |
| **WASD** | Left stick (move) |
| **X** | Start |
| **Z** | Back |
| **L / P** | X / Y |

(Defaults `keybind_a` was `0xBA` ';'; remapped to include Enter `0x0D`. Full list under
`[HID.WinKey]` in the config.)

**Use a real controller (recommended for Minecraft):** install **ViGEmBus** in the guest,
then plug an Xbox/generic gamepad into your Mac — Moonlight Web passes it through the HTML5
Gamepad API → Sunshine → ViGEmBus → Xenia sees a native Xbox pad. (Set `hid = "any"` or
`"sdl"` so both keyboard and controller work.)

---

## 5. Adding your own games
1. Copy a legally-owned dump to the guest:
   `scp game.iso arena@192.168.3.202:C:/X360Arena/roms/`
2. Open it in **Xenia Manager** (or make a desktop shortcut to `xenia_canary.exe "path\to\game"`)
3. Per-game flags live in `config/games/<slug>.toml`; the global config holds defaults.
4. If a game shows "Launching new title" or stays at a menu, it likely needs a **Title Update**
   (§3). BO2 is broken on Xenia; BO1 is partial (see `docs/F0-research.md`).

---

## 6. Quick troubleshooting
- **Stream page loads but no video** → WebRTC ports; see §1 (already fixed; re-check firewall + `web-server` task).
- **Clicks do nothing in a game** → it's controller-driven; use the keyboard map (§4) or a controller. `keyboard_mode` must be `1`.
- **Game wedges with ~30 MB RAM, no window** → it was launched over SSH/Task; launch from the desktop instead.
- **Black Proxmox console** → expected (emulated VGA disabled for NVENC); use SSH or the stream.
- **GPU busy / video-lab needed** → `deploy/control.sh xbox-off` returns the 3090 Ti to VM 100.
