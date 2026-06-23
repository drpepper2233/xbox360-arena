# Xbox 360 Arena — Handoff Verification Ledger

This document tracks the final validation gates and system readiness for deployment.

## 1. Handoff Verdict
* **Status:** `[ TODO: READY | READY WITH RISKS | NOT READY ]`
* **Assessed On:** `[ TODO: Date of Assessment ]`
* **Assessed By:** `[ TODO: Auditor / Role ]`

> [!NOTE]
> The handoff is considered **READY** only when all Layer 18 validation gates pass under independent audit.

---

## 2. Access URL & Credentials
* **Moonlight-web Client URL:** `http://<TODO: Moonlight Web Host IP>:<PORT>`
* **Sunshine Admin Interface:** `https://<TODO: Guest VM IP>:47990`
* **Remote Desktop Connection (RDP):** `<TODO: Guest VM IP>`
* **Access Credentials:**
  * Windows Guest Account: `<TODO: Username>` / `<TODO: Password>`
  * Sunshine Admin Account: `<TODO: Sunshine Admin Username>` / `<TODO: Sunshine Admin Password>`

---

## 3. System Inventory
The following components have been provisioned and configured:

| Component | Target Version / Spec | Status / Verified ID |
|---|---|---|
| **Host OS** | Proxmox VE | `[ TODO: Proxmox Version ]` |
| **GPU** | NVIDIA RTX 3090 Ti | `[ TODO: PCIe Address Verified ]` |
| **Guest OS** | Windows 11 | `[ TODO: Win11 Build Version ]` |
| **Graphics Driver** | NVIDIA Game Ready Driver | `[ TODO: Driver Version ]` |
| **Emulator** | Xenia Canary | `[ TODO: Canary Commit/Version ]` |
| **Frontend** | Xenia Manager | `[ TODO: Manager Version ]` |
| **Host Streamer** | Sunshine | `[ TODO: Sunshine Version ]` |
| **Client Streamer** | Moonlight-web (WASM) | `[ TODO: Client Version ]` |

---

## 4. Game Roster Configuration
Verification status of the configured games:

| # | Game Title | Title ID | Target Tier | Verification Status | Notes / Logs |
|---|---|---|---|---|---|
| 1 | Minecraft: Xbox 360 Edition | `584111F7` | Playable | `[ TODO: PASS / FAIL ]` | Requires `license_mask = 1` |
| 2 | Red Dead Redemption | `5454082B` | Playable | `[ TODO: PASS / FAIL ]` | Requires cache mount + 60fps patch |
| 3 | Skate 3 | `454108E6` | Playable | `[ TODO: PASS / FAIL ]` | Requires VSync disabled |
| 4 | Castle Crashers | `584108A7` | Playable | `[ TODO: PASS / FAIL ]` | Requires `license_mask = 1` |
| 5 | Fable II | `4D5307F1` | Playable | `[ TODO: PASS / FAIL ]` | Requires `readback_resolve = "full"` |
| 6 | Halo 3 | `4D5307E6` | Playable | `[ TODO: PASS / FAIL ]` | Requires HDR/lighting patch |
| 7 | Gears of War | `4D5307D5` | Playable | `[ TODO: PASS / FAIL ]` | Standard configuration |
| 8 | Sonic Generations | `53450849` | Playable | `[ TODO: PASS / FAIL ]` | Standard configuration |
| 9 | Halo: Reach | `[ TODO ]` | Playable | `[ TODO: PASS / FAIL ]` | Verify Title ID |
| 10 | Banjo-Kazooie: Nuts & Bolts | `[ TODO ]` | Playable | `[ TODO: PASS / FAIL ]` | Verify Title ID |
| - | COD Black Ops 1 (Extra) | `41560855` | Runs | `[ TODO: PASS / FAIL ]` | Best-effort, shader stutters expected |
| - | COD Black Ops 2 (Extra) | `415608C3` | Broken | `[ TODO: PASS / FAIL ]` | Best-effort, crashes expected |

---

## 5. Recovery & Backups
### VM Backup
* **Schedule:** `[ TODO: Backup Schedule/Policy ]`
* **Target Storage:** `[ TODO: Backup Storage Target ]`
* **Proxmox Backup Command:**
  ```bash
  # TODO: Document restore command
  vzdump 360 --compress zstd --storage <TODO>
  ```

### Configuration Files Backup
All emulator and streaming configurations are backed up inside this repository under the `config/` directory.
* **Xenia Canary Configs:** `config/games/*.toml`
* **Sunshine Config:** `config/sunshine.conf` (or equivalent)
* **Moonlight-web Config:** `config/moonlight-web/`
