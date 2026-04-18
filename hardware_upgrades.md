# Hardware Upgrade Plan

Migration from mixed-drive / mdadm RAID 1 setup to ZFS pools on an LSI 9300-16i HBA.

**Strategy:** Two shutdowns total. First shutdown installs the HBA and connects all new drives externally via cables routed out of the case. All burn-in, pool creation, and data migration happens with both old and new drives online simultaneously. Second (final) shutdown is a physical reorganization: retired drives come out, new drives move into the case bays. Old drives are never physically disturbed until the new setup is proven.

## Goals

- Replace Plex's 4TB + 640GB drive split with a proper RAIDZ2 media pool
- Replace personal01 mdadm RAID 1 (2× 1TB) with a 2× 8TB enterprise mirror
- Zero data loss, minimal Plex/Immich downtime
- Single controller for all HDDs (hot-swap, consistent error reporting)
- Fit everything in the existing Fractal Define R5 (8× 3.5" bays), leaving 2 bays free for future expansion

## Target Hardware State

| Component | Status |
|---|---|
| LSI 9300-16i HBA (IT mode) | **NEW** — replaces current cheap SATA expansion card |
| 4× 26TB Seagate Exos recertified (media pool, on HBA) | **NEW** — `ST26000NM000C` from ServerPartDeals, mfr-recert 5yr warranty |
| 2× 8TB Dell G14 enterprise (personal pool, on HBA) | **NEW** — `J7W80`, 7.2K RPM SATA 6Gb/s, 256MB cache, new (not recert) |
| 500GB OS NVMe (M.2) | unchanged |
| Retire: 2× 1TB (personal01 RAID 1), 4TB Seagate Barracuda SMR (plex01), 640GB Hitachi (plex02), 480GB ADATA (plex03), cheap SATA card | **REMOVE** |

### Why the 4TB Barracuda is retired

The existing ST4000DM004 is **DM-SMR** (confirmed via `smartctl -i` showing `Model Family: Seagate BarraCuda 3.5 (SMR)`). SMR drives are unsafe in RAID/ZFS — they time out during resilvers, can get kicked from pools, and have catastrophic random-write performance once their CMR cache fills. Retiring this drive completely.

## Target Storage State

| Pool | Layout | Drives | Usable | Workload |
|---|---|---|---|---|
| `media` | RAIDZ2 | 4× 26TB | ~46 TiB | Plex, audiobooks, torrents |
| `personal` | single 2-way mirror | 2× 8TB | ~7.3 TiB | Immich photos, documents, backups |
| OS (`/`) | single NVMe | 500GB | ~450 GiB | Ubuntu + Docker + Vaultwarden |

**Why 2-way mirror (not striped mirrors) for personal:** Gigabit LAN caps throughput at 125 MB/s. A 2-way 8TB 7200-RPM enterprise mirror already delivers ~250 MB/s sequential write and ~400-500 MB/s sequential read — disk isn't the bottleneck for Immich workloads. Keeping 2 bays free now preserves the option to add 2 more 8TB drives later and promote to striped mirrors (RAID 10), add a mirrored SSD special vdev for metadata acceleration, or widen the media RAIDZ2 via ZFS 2.3 RAIDZ expansion.

### PCIe slot constraints (B550 Eagle WIFI6)

Per the GIGABYTE manual and confirmed via `lspci` tree inspection:

| Slot | Source | Physical | Electrical | Notes |
|---|---|---|---|---|
| PCIEX16 | CPU | x16 | PCIe 4.0 x16 | GPU only (RTX 3090); can't bifurcate to share with HBA |
| PCIEX1_1..4 | Chipset | x16 | **PCIe 3.0 x1** | All four x16-physical slots are wired x1 electrical |

**Consequence for the HBA:** regardless of which chipset slot the 9300-16i is installed in, it negotiates **PCIe 3.0 x1 ≈ 985 MB/s**. Slot choice is driven by cooling (place above the bottom intake fan) and cable routing, not by bandwidth.

**Impact on workloads:**

| Workload | Affected? |
|---|---|
| Plex streams (per-client ≤30 MB/s) | No |
| Immich uploads (gigabit LAN cap 125 MB/s) | No |
| Torrent writes (network-bound) | No |
| Monthly scrubs (6 drives reading in parallel, can exceed 1 GB/s) | Yes — ~50% longer than x4 would run |
| Resilver after drive failure (~16h → ~24h for 26TB) | Yes — more exposure window, but tolerable |

Acceptable tradeoff. Upgrade path would be a motherboard swap (B550/X570 variant with a real PCIEX4 chipset slot) — deferred indefinitely.

## Bay & Port Accounting

Final state: 4× 26TB + 2× 8TB = **6 drives in 6 HDD bays, 2 bays free, 6 of 16 HBA ports used.**

**During migration (between shutdown #1 and shutdown #2):** existing drives stay in their current bays; new drives sit externally on cables routed out of the case. Bays never overflow because physical reorganization happens all at once in shutdown #2.

| Phase | Internal (MOBO SATA) | Internal (HBA) | External (HBA via extended cables) |
|---|---|---|---|
| Now | 2×1TB + 4TB + 640GB (+ ADATA on bracket) | — | — |
| After shutdown #1 | 2×1TB + 4TB + 640GB | — | 4×26TB + 2×8TB |
| After shutdown #2 | — | 4×26TB + 2×8TB | — |

Note: the ADATA SSD is retired during shutdown #1 (no data). The cheap SATA card is also removed during shutdown #1 — existing 4 HDDs fit on the 4 MOBO SATA ports directly.

## Budget

| Item | Qty | Unit | Subtotal |
|---|---|---|---|
| Seagate Exos 26TB recertified (`ST26000NM000C`) | 4 | $489.99 | $1,959.96 |
| Dell G14 `J7W80` 8TB enterprise (new) | 2 | $249.00 | $498.00 |
| LSI 9300-16i HBA (IT mode) | 1 | ~$100 | ~$100 |
| SFF-8643 → 4× SATA forward breakout cable | 2 | $15 | $30 |
| SATA power splitter (if PSU bag runs short) | 0–2 | $10 | $0–20 |
| **Drives subtotal (SPD cart)** | | | **$2,457.96** |
| **Total with HBA + cables** | | | **~$2,590** |

## Pre-work

### Install ZFS tooling

```bash
sudo apt update
sudo apt install -y zfsutils-linux smartmontools
zfs version   # must be >= 2.2
```

### Snapshot current disk layout

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,WWN,MOUNTPOINT > ~/preupgrade-disks.txt
sudo smartctl --scan >> ~/preupgrade-disks.txt
cat /proc/mdstat >> ~/preupgrade-disks.txt
cp /etc/fstab ~/preupgrade-fstab.txt
cp /etc/mdadm/mdadm.conf ~/preupgrade-mdadm.conf.txt
```

Copy these to your phone or another machine — recovery reference if something goes wrong during shutdown #1.

### Pre-check SATA power capacity

Count SATA power connectors on your PSU cables (routed + in the bag). You need:
- 4 for existing internal drives (2×1TB + 4TB + 640GB — the ADATA SSD will be removed during shutdown #1)
- 6 for new external drives (4× 26TB + 2× 8TB)

Most 1200W PSUs ship with 2–3 SATA power cables at 3–4 connectors each = 6–12 connectors. Likely fine, but verify before shutdown #1.

Daisy-chain rule: **max 4 drives per SATA power cable** (~120W per cable at spin-up peak).

---

## Shutdown #1 — Install HBA, connect new drives externally

1. Power down.
2. Remove cheap SATA expansion card — retire.
3. Remove ADATA SSD — retire (no data).
4. Install LSI 9300-16i in **PCIEX1_4 (bottom x16-physical chipset slot)** — sits directly above the bottom intake fan for active cooling on the heatsink. See "PCIe slot constraints" below for why the slot choice doesn't affect bandwidth on this board.
5. **Keep existing drives in place** (2×1TB + 4TB Barracuda + 640GB Hitachi), cabled to the 4 motherboard SATA ports.
6. Connect **4× 26TB Exos + 2× 8TB Dell** externally:
   - 2× SFF-8643 → 4× SATA forward breakout cables from HBA internal ports, routed out the rear PCI slots or side panel gap (only 6 of the 8 SATA leads will be used — leave the other 2 tied back)
   - New drives sit on a towel/rack outside the case during migration
   - SATA power from PSU via extended cables or splitters
7. Label each new drive's tray/case with last 4 of its serial (Sharpie) for future physical identification.

### After boot — verify before doing anything destructive

```bash
# HBA visible, in IT mode
lspci | grep -i sas
sudo dmesg | grep -iE "mpt3sas|firmware version"   # firmware string should end in "-IT"

# Pre-existing mounts returned
df -h /mnt/personal01 /mnt/plex01 /mnt/plex02
cat /proc/mdstat                                    # personal01 clean?

# All 6 new drives visible via HBA
lsblk -o NAME,SIZE,MODEL,SERIAL | grep -iE "ST26000|J7W80|HUS728T8"

# SMART works on every new drive
for d in /dev/sd{a..z}; do
  sudo smartctl -i $d 2>/dev/null | grep -E "Device Model|Serial"
  echo "---"
done
```

If any check fails, stop and diagnose. Do not proceed to burn-in or pool creation.

---

## Migration Phase (all online — no downtime beyond service restarts)

### M1 — Burn in all 6 new drives

Run in parallel across all new drives, in tmux/screen so sessions survive disconnects.

First, figure out what the J7W80 actually is — Dell OEM drives are typically rebadged Seagate Exos or HGST Ultrastar. Check the underlying model:
```bash
sudo smartctl -i /dev/disk/by-id/ata-* | grep -E "Model|Family"
```
Adjust the glob patterns below based on what model string shows up for the J7W80 drives.

**Option A (fast, ~20h total):** SMART long self-test only
```bash
for d in /dev/disk/by-id/ata-ST26000NM* /dev/disk/by-id/ata-*8TB-J7W80*; do
  sudo smartctl -t long $d
done
# Check back after ~20h (26TB) / ~12h (8TB):
for d in /dev/disk/by-id/ata-ST26000NM* /dev/disk/by-id/ata-*8TB-J7W80*; do
  sudo smartctl -a $d | grep -E "Reallocated_Sector|Current_Pending|Offline_Uncorrectable|UDMA_CRC_Error|self-test"
done
# All counters should be 0; self-test result should be "Completed without error"
```

**Option B (thorough, ~3–4 days for 26TB drives):** full `badblocks -wsv` destructive write-read-verify
```bash
# Per drive, in separate tmux windows
sudo badblocks -b 4096 -wsv -o /root/bb-ST26000-A.log /dev/disk/by-id/ata-ST26000NM000C-XXXX
```
Worth the extra time for the recertified Exos drives (they've already had a previous life). The Dell J7W80 drives are new stock so Option A is sufficient for them.

Any drive with reallocated sectors, pending sectors, or UDMA CRC errors after burn-in → RMA it before building the pool.

### M2 — Build `media` pool (RAIDZ2, 4× 26TB)

```bash
# Get stable device IDs — NEVER use /dev/sdX in zpool create
ls -l /dev/disk/by-id/ | grep -i ST26000

sudo zpool create -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O recordsize=1M \
  -O mountpoint=/mnt/media \
  media raidz2 \
    /dev/disk/by-id/ata-ST26000NM000C-... \
    /dev/disk/by-id/ata-ST26000NM000C-... \
    /dev/disk/by-id/ata-ST26000NM000C-... \
    /dev/disk/by-id/ata-ST26000NM000C-...

sudo zpool status media
sudo zfs list media

# Datasets matching existing layout — keeps compose-file diffs minimal
sudo zfs create media/plex01
sudo zfs create media/plex02
sudo chown -R root:plex-rw /mnt/media/plex01 /mnt/media/plex02
sudo chmod -R 2775 /mnt/media/plex01 /mnt/media/plex02
```

### M3 — Build `personal` pool (single 2-way mirror, 2× 8TB)

```bash
# Confirm device IDs for the Dell drives — J7W80 is typically a rebadged
# Seagate Exos or HGST Ultrastar; use whichever model string shows up.
ls -l /dev/disk/by-id/ | grep -iE "J7W80|8TB|HUS728|ST8000"

sudo zpool create -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  -O mountpoint=/mnt/personal \
  personal \
    mirror /dev/disk/by-id/ata-DELL-8TB-J7W80-A /dev/disk/by-id/ata-DELL-8TB-J7W80-B

sudo zfs create personal/photos
sudo zfs create personal/documents
sudo zfs create personal/backups

sudo chown -R root:personal-rw /mnt/personal
sudo chmod -R 2775 /mnt/personal
sudo zpool status personal
```

**Future expansion note:** To promote to striped mirrors (RAID 10-equivalent) later, buy 2 more matching 8TB drives, burn them in, then:
```bash
sudo zpool add personal mirror /dev/disk/by-id/ata-DELL-8TB-J7W80-C /dev/disk/by-id/ata-DELL-8TB-J7W80-D
```
New writes stripe across both vdevs; existing data stays on the first mirror until ZFS rebalances naturally over writes.

### M4 — Migrate Plex / audiobooks / torrent data (Plex still running)

Long-running, run each in its own tmux window:

```bash
sudo rsync -aHAXx --info=progress2 /mnt/plex01/ /mnt/media/plex01/
sudo rsync -aHAXx --info=progress2 /mnt/plex02/ /mnt/media/plex02/
```

### M5 — Cutover Plex / audiobooks / torrent (~5 min downtime)

```bash
cd ~/workspace/home-server/plex       && docker compose stop
cd ~/workspace/home-server/torrent    && docker compose stop
cd ~/workspace/home-server/audiobooks && docker compose stop

# Final incremental rsync with --delete
sudo rsync -aHAXx --delete --info=progress2 /mnt/plex01/ /mnt/media/plex01/
sudo rsync -aHAXx --delete --info=progress2 /mnt/plex02/ /mnt/media/plex02/
```

**Required compose-file edits (service-blocking — must be done before `docker compose up -d`):**

Sweep `/mnt/plex01` → `/mnt/media/plex01`, `/mnt/plex02` → `/mnt/media/plex02`.

| File | Lines | Change |
|---|---|---|
| `plex/docker-compose.yml` | 16, 17 | both plex01/plex02 bind mounts |
| `torrent/docker-compose.yml` | 63, 64, 77, 78, 92, 93 | qbittorrent + sonarr + radarr volume stanzas |
| `audiobooks/docker-compose.yml` | 9, 10 | `/mnt/plex01/audiobooks` and `/mnt/plex02/audiobooks` bind mounts |

```bash
cd ~/workspace/home-server/plex       && docker compose up -d
cd ~/workspace/home-server/torrent    && docker compose up -d
cd ~/workspace/home-server/audiobooks && docker compose up -d
```

**Documentation edits (non-blocking — do while services run, or batch with M7 docs at the end):**

| File | Lines | Change |
|---|---|---|
| `plex/README.md` | 3, 15–18 | narrative + mount table |
| `plex/setup.md` | 39–42 | library paths in admin UI steps |
| `torrent/README.md` | 18, 22, 23 | download-path prose + table |
| `torrent/setup.md` | 44, 45, 60, 62, 74, 82 | Sonarr/Radarr/qBittorrent root-folder instructions |
| `torrent/scripts/sonarr_import.sh` | 17, 18, 265 | example commands in header + trailing comment |
| `audiobooks/README.md` | 12 | library-path note |
| `audiobooks/setup.md` | 6, 24 | mkdir + library-add instructions |

**Verify** before moving on:
- Plex library loads without "missing paths" warnings
- A random movie plays end-to-end
- qBittorrent sees its save path
- Audiobookshelf sees its library

### M6 — Migrate Immich / document-pipeline / backups (personal01 → personal)

Initial rsync while services run:

```bash
sudo rsync -aHAXx --info=progress2 /mnt/personal01/photos/    /mnt/personal/photos/
sudo rsync -aHAXx --info=progress2 /mnt/personal01/documents/ /mnt/personal/documents/
sudo rsync -aHAXx --info=progress2 /mnt/personal01/backups/   /mnt/personal/backups/
```

### M7 — Cutover Immich / document-pipeline (~5 min downtime)

```bash
cd ~/workspace/home-server/photos && docker compose stop
cd ~/workspace/home-server/api    && docker compose stop   # document-pipeline
sudo crontab -e   # comment out the backup.sh cron line

# Final incremental rsync with --delete
sudo rsync -aHAXx --delete --info=progress2 /mnt/personal01/photos/    /mnt/personal/photos/
sudo rsync -aHAXx --delete --info=progress2 /mnt/personal01/documents/ /mnt/personal/documents/
sudo rsync -aHAXx --delete --info=progress2 /mnt/personal01/backups/   /mnt/personal/backups/
```

**Required service-config edits (blocking — must be done before `docker compose up -d`):**

Sweep `/mnt/personal01` → `/mnt/personal`.

| File | Line(s) | Change |
|---|---|---|
| `photos/docker-compose.yml` | 26 | Immich `/usr/src/app/upload` bind mount |
| `api/docker-compose.yml` | 200 | document-pipeline `/vault` bind mount |
| `scripts/backup.sh` | 2, 23, 38, 46, 162 | comment + `DEST` + preflight + `BACKUP_ROOT` |
| `scripts/test/backup.bats` | 36, 99, 112, 137, 186, 252, 268, 280, 289, 332, 342, 350 | test fixture paths — update in lockstep with `backup.sh` so tests still pass |

**Documentation edits (non-blocking — can defer until after the verification window):**

| File | Lines | Change |
|---|---|---|
| `photos/README.md` | 30 | photos-path table |
| `photos/setup.md` | 16, 17 | `mkdir` + `chown` instructions |
| `notes/setup.md` | 23, 24, 25 | `/mnt/personal01/obsidian-vault` → `/mnt/personal/obsidian-vault` (rmfakecloud sync path) |

```bash
cd ~/workspace/home-server/photos && docker compose up -d
cd ~/workspace/home-server/api    && docker compose up -d

# Test backup manually
./scripts/backup.sh
ls -lh /mnt/personal/backups/
```

Once backup works: re-enable cron (`sudo crontab -e`, uncomment).

### M8 — Verification window: 24–48h

Let the new pools run with real workload for 1–2 days before shutdown #2. Check daily:

```bash
sudo zpool status media personal
# Look for: state ONLINE, no errors, no degraded vdevs
```

Smoke-test daily:
- Upload a photo → confirm it appears
- Play a movie → confirm it streams (with NVENC enabled from earlier work)
- Trigger a manual backup → confirm it succeeds

---

## Shutdown #2 — Final physical reorganization

This is the invasive shutdown. You're unplugging and re-seating ~11 drives.

### Before shutdown

```bash
# Stop services to prevent writes during transition
cd ~/workspace/home-server && for d in plex torrent audiobooks photos api notes; do
  (cd $d && docker compose stop)
done
sudo crontab -e   # comment out backup.sh cron again

# Unmount and stop the old personal01 array cleanly
sudo umount /mnt/personal01
sudo mdadm --stop /dev/md0

# Export pools before physically moving drives
sudo zpool export media
sudo zpool export personal

# Clean up fstab entries for retired mounts
sudo sed -i '/\/mnt\/personal01/d; /\/mnt\/plex0[12]/d' /etc/fstab

sudo shutdown now
```

### Physical work

1. Remove all cables to external drives (disconnect the SFF-8643 breakouts, unplug external SATA power).
2. Remove from internal bays:
   - 2× 1TB (personal01 RAID 1) — retire, wipe later via USB dock
   - 4TB Seagate Barracuda (plex01) — retire (SMR, unsafe for anything RAID; can be reused as cold standalone backup via USB dock)
   - 640GB Hitachi (plex02) — retire (41k hours, dead soon anyway)
3. Install into internal bays, all on the HBA:
   - 4× 26TB Exos → bays 1–4
   - 2× 8TB Dell → bays 5–6
   - Bays 7–8 left empty (future expansion)
4. Cable each drive to an HBA port via the two SFF-8643 breakouts (previously used externally, now internal routing). Only 6 of the 8 SATA leads are used — tuck the spare 2 back neatly or leave accessible near bays 7–8 for a future drop-in.
5. Close the case.

**Dell drive trays:** The Dell J7W80 drives ship in Dell G14 3.5" caddies (part `X7K8W` or similar). Remove the drive from the Dell caddy before mounting in the Fractal R5 — the Dell caddy is designed for Dell PowerEdge hot-swap bays and won't fit the R5's drive sleds. Four screws through the side rails hold the drive in the caddy; undo them, lift the drive out, then mount into the R5's drive tray using the R5's included screws (bottom-mount). Keep the Dell caddies in storage in case you ever RMA the drive.

### After boot

```bash
# Pools should auto-import; if not:
sudo zpool import -a
sudo zpool status media personal

# Confirm all services come up
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E "immich|document|plex|audiobook|qbit|sonarr|radarr"

# Smoke-test Immich photo load, Plex playback, backup run
./scripts/backup.sh

# Re-enable cron
sudo crontab -e
```

---

## Ongoing operations

### Monthly scrubs

To avoid contention on the PCIe x1 bottleneck, stagger these scrubs (e.g., 1st vs 15th of the month) and schedule them for low-usage hours.

```bash
sudo systemctl enable --now zfs-scrub-monthly@media.timer
sudo systemctl enable --now zfs-scrub-monthly@personal.timer

# Stagger 'personal' scrub to the 15th to avoid PCIe bottleneck during 'media' scrub
sudo mkdir -p /etc/systemd/system/zfs-scrub-monthly@personal.timer.d/
sudo tee /etc/systemd/system/zfs-scrub-monthly@personal.timer.d/override.conf > /dev/null <<'EOF'
[Timer]
OnCalendar=
OnCalendar=*-*-15 03:00:00
EOF
sudo systemctl daemon-reload
sudo systemctl restart zfs-scrub-monthly@personal.timer

# Verify both timers show the expected next-fire times
systemctl list-timers 'zfs-scrub-monthly@*.timer'
```

### Snapshots for personal (not media)

```bash
sudo apt install -y zfs-auto-snapshot
# Default policy: 4 hourly + 24 daily + 4 weekly + 12 monthly
# Disable on media to avoid snapshot bloat from Plex writes:
sudo zfs set com.sun:auto-snapshot=false media
```

### Prometheus ZFS metrics

Enable `--collector.zfs` in the existing node_exporter, or add `zfs_exporter` to `monitoring/docker-compose.yml`.

### Post-migration documentation & observability cleanup

These files reference the old drive layout but don't block services from running. Clean them up after shutdown #2 to keep the repo honest.

**Top-level docs:**

| File | Change |
|---|---|
| `hardware.md` | Rewrite "Current Hardware" and "Drive Layout" tables for 4× 26TB Exos + 2× 8TB Dell on LSI 9300-16i, ZFS pools `media` and `personal`, retired drives removed |
| `setup.md` (top-level) | Rewrite drive-provisioning section (`/etc/fstab` examples, mdadm RAID 1 instructions, plex01/plex02/plex03 mkdir steps) for ZFS pool creation. Lines 28–32, 244, 248, 254, 258, 261, 267–270, 275, 284, 287, 293–296, 319, 320, 329, 374–377, 380–382, 389, 393 all reference the old layout |

**Operational scripts:**

| File | Lines | Change |
|---|---|---|
| `scripts/check-disk.sh` | 9 | Loop target list: `/mnt/plex01 /mnt/personal01` → `/mnt/media /mnt/personal` |
| `scripts/setup/phase4-drives.sh` | 57–196 | Legacy — this script creates mdadm RAID 1 and ext4 mounts for the old layout. After migration it's obsolete. Either rewrite as a ZFS-pool-creation script for future fresh installs, mark as legacy with a banner comment, or delete. |

**Monitoring:**

| File | Change |
|---|---|
| `monitoring/config/diskspace.conf` | Lines 4, 7, 10: replace `[/mnt/plex01]` / `[/mnt/plex02]` / `[/mnt/personal01]` stanzas with `[/mnt/media]` and `[/mnt/personal]`. Drop the plex02 stanza entirely (no more overflow drive). Also consider dropping the per-mount diskspace exporter in favor of ZFS pool-level metrics (see above). |
| `monitoring/grafana-dashboards/home-server.json` | Lines 621, 667 (read/write rate PromQL) and 829–845 (legend value mappings) use `label_replace` to rename `sda..sde` to `personal01-a`, `personal01-b`, `plex01`, `plex02`, `plex03`. Post-migration the drives are on the HBA (typically re-enumerated) and the old mappings are wrong. Options: (a) re-map the `label_replace` chain to the new drive letters and pool names (`media-1`..`media-4`, `personal-a`, `personal-b`), or (b) switch the panel to use ZFS-native metrics (`node_zfs_*`) for pool-level I/O. **(b) is the cleaner path** — ZFS abstracts per-drive detail and matches how you reason about the pools. |
| `monitoring/grafana-provisioning/dashboards/dashboards.yaml` | No change — provisioning pointer only, no mount paths. |

None of these block the migration. Prioritize in this order after shutdown #2 stabilizes:
1. `hardware.md` + top-level `setup.md` (keep repo truthful)
2. `monitoring/config/diskspace.conf` (so Prometheus stops alerting on missing mounts)
3. `scripts/check-disk.sh` (so cron health checks stop failing)
4. Grafana dashboard (nicest to have — can be done when enabling ZFS metrics)
5. `scripts/setup/phase4-drives.sh` (legacy — only matters on next fresh install)

---

## Rollback points

| After phase | If things go wrong, how to recover |
|---|---|
| Shutdown #1 | Reinstall cheap SATA card, reseat old drives. No pool exists yet; nothing cut over. |
| M1–M3 (burn-in, pool build) | `zpool destroy` — no user data involved yet. |
| M4 (media rsync running) | Kill rsync; Plex still running off old drives. |
| M5 (post-Plex cutover) | Revert compose files via git; old plex01/plex02 drives still mounted and untouched. |
| M6 (personal rsync running) | Kill rsync; Immich still running off personal01. |
| M7 (post-Immich cutover) | Revert `photos/`, `api/`, `scripts/backup.sh` via git; personal01 still intact. |
| M8 (verification window) | Full rollback available — flip compose files back, remount personal01, restart services. |
| Shutdown #2 in progress | Reinstall old drives, revert compose files, re-import old personal01 mdadm array. |
| After shutdown #2 boot | Pools should auto-import. If not, `zpool import -d /dev/disk/by-id`. Old drives available as cold backup via USB dock if needed. |

---

## Decisions (finalized)

- [x] ~~Personal pool topology~~ — 2× 8TB single mirror (2 bays free for future RAID 10 promotion)
- [x] ~~Drive selection~~ — 4× 26TB Seagate Exos + 2× 8TB Dell J7W80 ($2,457.96 SPD cart)
- [x] ~~Cable plan~~ — all HDDs on HBA (hot-swap for all pools); 2× Cable Matters 1m SFF-8643 → 4× SATA forward breakout
- [x] ~~Plex dataset layout~~ — preserving `plex01`/`plex02` split to minimize compose diffs
- [x] ~~HBA slot~~ — PCIEX1_4 (bottom x16-physical chipset slot, above bottom intake fan). All 4 chipset slots on this board are x1 electrical, so slot choice is driven by cooling, not bandwidth. HBA negotiates PCIe 3.0 x1 ≈ 985 MB/s — acceptable bottleneck.
- [x] ~~Burn-in depth~~ — Option B (`badblocks -wsv`, ~3–4 days) for the 4 recertified Exos drives; Option A (SMART long self-test, ~12h) for the 2 new Dell J7W80s
- [x] ~~Special vdev~~ — **not including**. Immich thumbnail workload doesn't justify the added complexity and extra drives. Defer indefinitely.
