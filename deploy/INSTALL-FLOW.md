# Windows Install Flow

BUILD-2 is author-only. These files are staged for the next infra layer; do not run Proxmox or guest commands from this layer.

## Files

- `deploy/autounattend.xml`: Windows 11 Pro 25H2 unattended answer file.
- `deploy/bootstrap.ps1`: first-logon bootstrap for remote access and `guest-setup.ps1`.
- `deploy/guest-setup.ps1`: BUILD-1 in-guest stack installer, expected at `C:\X360Arena\deploy\guest-setup.ps1` after staging.

## Credentials

Local admin user: `arena`

Password placeholder in `autounattend.xml`:

```text
PLACEHOLDER_REPLACE_WITH_ARENA_PASSWORD
```

Replace that placeholder before building the autounattend ISO. It appears in both `AutoLogon` and `LocalAccount/Password`; the values must match.

The Windows 11 Pro product key in the answer file is Microsoft's public KMS client setup key for installation only. It does not activate Windows by itself.

## Autounattend ISO Build

From the repo root, build a small answer ISO that contains `autounattend.xml` at the root and the deploy payload under `deploy/`:

```bash
rm -rf build/autounattend-iso
mkdir -p build/autounattend-iso/deploy
cp deploy/autounattend.xml build/autounattend-iso/autounattend.xml
cp deploy/bootstrap.ps1 deploy/guest-setup.ps1 deploy/stream-client.md build/autounattend-iso/deploy/
if [ -d config ]; then cp -R config build/autounattend-iso/config; fi

xorriso -as mkisofs \
  -iso-level 3 \
  -J -R \
  -V X360AUTOUNATTEND \
  -o build/x360-arena-autounattend.iso \
  build/autounattend-iso
```

If `xorriso` is unavailable, use an equivalent ISO builder that preserves the same root layout:

```text
/autounattend.xml
/deploy/bootstrap.ps1
/deploy/guest-setup.ps1
/deploy/stream-client.md
/config/...                optional
```

Windows Setup must also see the existing virtio-win ISO. `autounattend.xml` includes driver paths for `vioscsi\w11\amd64` so Windows Setup can see the `scsi0` disk, and `NetKVM\w11\amd64` so the virtio NIC is available after install.

## Expected Setup Flow

1. The VM boots the Windows 11 25H2 ISO with the virtio-win ISO and the answer ISO attached.
2. Windows Setup reads `/autounattend.xml`.
3. Setup loads virtio storage/network drivers from the virtio-win ISO.
4. Setup wipes disk 0 and creates GPT partitions:
   - EFI: 260 MB, FAT32.
   - MSR: 16 MB.
   - Windows: remaining space, NTFS, drive `C:`.
5. Setup installs Windows 11 Pro to partition 3.
6. OOBE is suppressed, local admin `arena` is created, and `arena` auto-logs on.
7. `FirstLogonCommands` copies the mounted `deploy/` payload to `C:\X360Arena\deploy` and runs:

```powershell
C:\X360Arena\deploy\bootstrap.ps1 -InstallRoot C:\X360Arena -PayloadRoot C:\X360Arena\deploy
```

8. `bootstrap.ps1` enables Private network profile, RDP, OpenSSH Server, TCP/22 firewall, and then invokes:

```powershell
C:\X360Arena\deploy\guest-setup.ps1 -InstallRoot C:\X360Arena
```

## Guest Access

After first logon and bootstrap, the guest should be reachable over OpenSSH:

```bash
ssh arena@<guest-ip>
```

Use the same placeholder password value that was substituted into `autounattend.xml`.

From SSH, confirm the bootstrap marker and logs:

```powershell
Test-Path C:\X360Arena\.bootstrap-complete
Get-Content C:\X360Arena\logs\bootstrap.log -Tail 80
```

RDP should also be open for the same account:

```text
mstsc /v:<guest-ip>
```

## Recovery Notes

If OpenSSH is not reachable:

- Check the noVNC console for first-logon errors.
- Verify `C:\X360Arena\deploy\bootstrap.ps1` exists.
- Inspect `C:\Windows\Panther\UnattendGC\setupact.log`.
- Inspect `C:\X360Arena\logs\bootstrap.log` if the first-logon command reached PowerShell.

If Windows Setup cannot see the disk:

- Confirm the virtio-win ISO is attached.
- Confirm the virtio ISO contains `vioscsi\w11\amd64`.
- Rebuild the answer ISO without changing `autounattend.xml` placement at the root.

## Sources

- Microsoft Unattended Setup Reference: https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/
- Microsoft FirstLogonCommands: https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands
- Microsoft PnpCustomizationsWinPE DriverPaths: https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-pnpcustomizationswinpe-driverpaths
- Microsoft UEFI/GPT partition guidance: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions?view=windows-11
- Microsoft OpenSSH install/start/firewall guidance: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
- Microsoft Windows 11 Pro KMS client setup key: https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys
