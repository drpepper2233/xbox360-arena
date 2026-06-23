# VM-1 Spec — x360-arena (VMID 360) on bigbrother

**Date:** 2026-06-23  
**Host:** bigbrother (192.168.0.25)  
**Session:** .forge-session-484703000  
**Status:** VM running, Windows 11 25H2 installer booting

---

## VMID

**360** (confirmed free via `qm list`)

---

## GPU PCI Address (from VM 100)

```
hostpci0: 0000:2d:00,pcie=1
```

**RTX 3090 Ti PCI address: `0000:2d:00`**  
This is the address to use for VM-2's `hostpci0` passthrough.  
⚠️ VM 100 (videogen) is still running — GPU is NOT detached yet. GPU bind is VM-2's job.

---

## qm Commands Run

```bash
# 1. Create base VM
qm create 360 \
  --name x360-arena \
  --machine q35 \
  --bios ovmf \
  --cpu host \
  --cores 16 \
  --memory 32768 \
  --scsihw virtio-scsi-pci \
  --net0 virtio,bridge=vmbr0 \
  --ostype win11 \
  --agent 1

# 2. Add EFI disk (OVMF UEFI variables, 4M, pre-enrolled MS keys)
qm set 360 --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=1
# Result: local-lvm:vm-360-disk-0, size=4M, ms-cert=2023

# 3. Add TPM state (Windows 11 requirement)
qm set 360 --tpmstate0 local-lvm:1,version=v2.0
# Result: local-lvm:vm-360-disk-1, size=4M, version=v2.0

# 4. Add main NVMe disk (256G thin-provisioned on 1.9T NVMe)
qm set 360 --scsi0 local-lvm:256,discard=on,ssd=1
# Result: local-lvm:vm-360-disk-2, size=256G

# 5. Add CD-ROM slots and set boot order
qm set 360 --ide2 none,media=cdrom   # Win11 ISO slot
qm set 360 --ide0 none,media=cdrom   # virtio-win driver slot
qm set 360 --boot order='ide2;scsi0'

# 6. Attach ISOs
qm set 360 --ide0 local:iso/virtio-win.iso,media=cdrom
qm set 360 --ide2 local:iso/Win11_25H2_English_x64.iso,media=cdrom

# 7. Start VM
qm start 360
```

---

## ISOs

| ISO | Path on bigbrother | Source | Size |
|-----|-------------------|--------|------|
| Windows 11 25H2 x64 English | `/var/lib/vz/template/iso/Win11_25H2_English_x64.iso` | Microsoft software-download-connector API (legal, official CDN: software.download.prss.microsoft.com) | 7.9 GB |
| VirtIO drivers | `/var/lib/vz/template/iso/virtio-win.iso` | fedorapeople.org/groups/virt/virtio-win (stable-virtio) | 754 MB |

Win11 URL retrieved via: Python script implementing Fido.ps1's Microsoft API flow  
(`OrgId=y6jn8c31`, `ProfileId=606624d44113`, `EditionId=3321`, vlscppe + ov-df bot-check)

---

## Final VM Config (`qm config 360`)

```
agent: 1
bios: ovmf
boot: order=ide2;scsi0;ide0
cores: 16
cpu: host
efidisk0: local-lvm:vm-360-disk-0,efitype=4m,ms-cert=2023,pre-enrolled-keys=1,size=4M
ide0: local:iso/virtio-win.iso,media=cdrom,size=771138K
ide2: local:iso/Win11_25H2_English_x64.iso,media=cdrom,size=8273050K
machine: pc-q35-10.1
memory: 32768
name: x360-arena
net0: virtio=BC:24:11:E6:B2:4A,bridge=vmbr0
ostype: win11
scsi0: local-lvm:vm-360-disk-2,discard=on,size=256G,ssd=1
scsihw: virtio-scsi-pci
tpmstate0: local-lvm:vm-360-disk-1,size=4M,version=v2.0
```

---

## Storage Used

| Resource | Pool | Size |
|----------|------|------|
| EFI disk | local-lvm (vm-360-disk-0) | 4 MB |
| TPM state | local-lvm (vm-360-disk-1) | 4 MB |
| Main disk | local-lvm (vm-360-disk-2) | 256 GB (thin) |
| Win11 ISO | local dir | 7.9 GB |
| virtio-win ISO | local dir | 754 MB |

---

## Current State

- VM 360 (x360-arena) **running** on bigbrother
- Boot order: Win11 ISO (ide2) → HDD (scsi0) → virtio-win (ide0)
- vTPM initialized and certified (RSA 2048 + ECC EK certificates)
- VM 100 (videogen) **untouched** — running normally, GPU NOT detached
- GPU passthrough **NOT configured** (VM-2 job)

---

## Verify Console

```
# From bigbrother host:
qm status 360          # should show: status: running
# noVNC console: https://192.168.0.25:8006 → VM 360 → Console
```

Windows Setup should be visible in the Proxmox noVNC console.

---

## VM-2 Handoff Notes

- GPU to bind: `hostpci0: 0000:2d:00,x-vga=1,pcie=1`
- VM 100 must be powered off before GPU bind
- After bind, add: `--hostpci0 0000:2d:00,x-vga=1,pcie=1`
- Remove default VGA: `--vga none`
