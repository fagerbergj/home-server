# Immich — Setup

## Prerequisites

Make sure `scripts/setup/phase4-ids.sh` has been run — it fills in `PUID` and `PGID` in `docker-compose.yml` automatically.

## 1. Generate the env file

```bash
./generate-env.sh
```

## 2. Create the photo directory

```bash
sudo mkdir -p /mnt/personal01/photos
sudo chown immich:personal-rw /mnt/personal01/photos
```

## 3. Start all services

```bash
docker compose up -d
```

Verify everything came up:
```bash
docker compose ps
```

## 4. Create your admin account

Open `http://<server-ip>:2283` and create your admin account on first visit.

## Verify

1. Upload a test photo via the web UI — it should appear in the timeline
2. Check that the ML container is processing it:
   ```bash
   docker compose logs -f immich-machine-learning
   ```
   You should see face detection and CLIP encoding jobs run against the upload
