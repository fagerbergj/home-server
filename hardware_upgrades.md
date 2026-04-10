we # Hardware Upgrades

Planned and completed hardware changes, with steps to execute them.

---

## Pending: OS Drive → NVMe + Repurpose ADATA SSD as plex03

### Background

The current OS drive (480GB ADATA SU650 SSD) has 11 pending bad sectors and
37,705 power-on hours. The SATA cable failed in April 2026, causing I/O errors
across the system. A replacement 500GB NVMe has been ordered.

Once swapped, the ADATA SSD will be wiped and mounted as `/mnt/plex03` —
additional overflow storage for re-downloadable Plex media, same role as plex02.

### Hardware changes

| | Before | After |
|---|---|---|
| OS drive | 480GB ADATA SU650 SATA SSD | 500GB NVMe (M.2 slot) |
| `/mnt/plex03` | — | 480GB ADATA SU650 (repurposed) |

---

### Step 1 — Clone the OS drive

The source drive must be idle during cloning. Boot from a USB live environment
(Clonezilla recommended — handles partition resizing automatically).

**Create a Clonezilla USB:**
```bash
# On any machine — download Clonezilla ISO and write to USB
dd if=clonezilla-live-*.iso of=/dev/sdX bs=4M status=progress
```

**Boot into Clonezilla and clone:**

1. Insert both the Clonezilla USB and ensure the NVMe is seated in the M.2 slot
2. Boot from USB (F12 on this board for boot menu)
3. Select: `device-to-device clone` → source `/dev/sdd` → dest `/dev/nvme0n1`
4. Enable "resize partition to fill target" — the NVMe may be slightly larger/smaller
5. Let it run (~20–30 min for 480GB)

Alternatively with `dd` from a live environment if you prefer manual control:
```bash
# Boot from live USB first, then:
sudo dd if=/dev/sdd of=/dev/nvme0n1 bs=4M status=progress conv=fsync
sudo partprobe /dev/nvme0n1

# Resize the LVM physical volume to use full NVMe capacity
sudo pvresize /dev/nvme0n1p3
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

---

### Step 2 — Update GRUB to boot from NVMe

After cloning, the NVMe has a copy of GRUB pointing at the old drive's UUIDs.
Boot from the NVMe (select it in the BIOS boot order) and verify it works.

If GRUB fails to find the OS:
```bash
# From the live USB, chroot into the NVMe install and reinstall GRUB
sudo mount /dev/nvme0n1p2 /mnt          # adjust partition as needed
sudo mount /dev/nvme0n1p1 /mnt/boot/efi
sudo chroot /mnt
grub-install /dev/nvme0n1
update-grub
exit
```

Check UUIDs are correct in `/etc/fstab` after booting:
```bash
blkid | grep nvme
cat /etc/fstab
# Update any UUIDs that reference the old sdd partitions
```

---

### Step 3 — Verify the system boots cleanly from NVMe

```bash
# Confirm OS is running from NVMe
lsblk
df -h /

# Confirm all Docker services are healthy
cd ~/workspace/home-server
docker compose ps   # run in each service directory as needed

# Check dmesg for any I/O errors
sudo dmesg | grep -i "error\|fail" | grep -v ACPI
```

---

### Step 4 — Wipe the ADATA SSD and set up as plex03

Once the system is confirmed healthy on the NVMe, wipe and reformat the old drive.

```bash
# Confirm which device is the old ADATA (double-check before wiping!)
sudo smartctl -a /dev/sdd    # should show ADATA SU650

# Wipe and partition
sudo wipefs -a /dev/sdd
sudo parted /dev/sdd mklabel gpt
sudo parted /dev/sdd mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L plex03 /dev/sdd1

# Get the new UUID
sudo blkid /dev/sdd1
```

Add to `/etc/fstab` (replace UUID with output from blkid above):
```
UUID=<new-uuid>  /mnt/plex03  ext4  defaults  0  2
```

Mount it:
```bash
sudo mkdir -p /mnt/plex03
sudo mount -a
df -h /mnt/plex03
```

---

### Step 5 — Set ownership and permissions for Plex

Match the existing plex01/plex02 permission model:
```bash
sudo chown root:plex-rw /mnt/plex03
sudo chmod 775 /mnt/plex03
```

Add to `hardware.md` drive layout table once complete.

---

### Step 6 — Update hardware.md

Update the hardware table to reflect:
- OS drive → 500GB NVMe
- New `/mnt/plex03` → 480GB ADATA SU650 (repurposed)
- Remove the ⚠️ note on plex02 if plex03 takes over non-critical media

---

### Notes

- The ADATA has 11 pending bad sectors — after reformatting as plex03, run
  `badblocks -w` on it (destructive, safe since it will be freshly wiped) to
  force sector remapping before putting media on it:
  ```bash
  sudo badblocks -w -v /dev/sdd
  ```
- plex03 is for re-downloadable media only (same policy as plex02) — do not
  store anything irreplaceable on it given its age and history
