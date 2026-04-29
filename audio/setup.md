# Audio Setup

One-time setup for the audio stack (faster-whisper + pyannote diarization).

## Prerequisites

- NVIDIA GPU with driver supporting CUDA 12.1+ (565+ recommended)
- NVIDIA Container Toolkit installed

## Hugging Face token (required)

pyannote's diarization model is open-source but gated for usage tracking. One-time:

1. Create a Hugging Face account: https://huggingface.co/join
2. Accept the licenses (click "Agree and access" on each — instant approval):
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
   - https://huggingface.co/pyannote/speaker-diarization-community-1 (transitive dep — pyannote pulls this for the PLDA backend)
3. Generate a **read** token: https://huggingface.co/settings/tokens
   - Type: Read
   - Name: anything (e.g. `home-server-audio`)
   - Copy the `hf_...` string immediately (it won't show again)
4. Add to the root `.env`:
   ```
   HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx
   ```

The token is used only on the first model download. After that the cache is offline.

## Build and start

```bash
cd ~/workspace/home-server/audio
docker compose build faster-whisper
docker compose up -d faster-whisper
docker logs -f faster-whisper
```

The first transcription request downloads pyannote models (~500 MB) into `./model-cache/`.

## Verify

```bash
curl http://localhost:8005/health
# {"status": "ok"}

curl http://localhost:8005/v1/audio/transcriptions \
  -F "file=@some-recording.webm" \
  -F "model=Systran/faster-whisper-large-v3"
```

## Speaker enrollment (optional, recommended)

By default the service returns generic `[SPEAKER_00]`, `[SPEAKER_01]` labels and pyannote chooses them inconsistently across recordings (Pat may be `SPEAKER_00` one session and `SPEAKER_02` the next). To get stable real names:

1. Record a clean ~10-30 second sample of each recurring speaker (one person talking, no crosstalk).
2. Enroll once per person:
   ```bash
   curl -F "file=@pat-sample.wav" -F "name=Pat" http://localhost:8005/v1/speakers/enroll
   curl -F "file=@sam-sample.wav" -F "name=Sam" http://localhost:8005/v1/speakers/enroll
   ```
3. Future transcriptions match each pyannote `SPEAKER_XX` against enrolled voiceprints. Above the similarity threshold (default 0.5), the label becomes the real name; otherwise it stays `SPEAKER_XX`.

Inspect / manage enrollments:

```bash
curl http://localhost:8005/v1/speakers              # list
curl -X DELETE http://localhost:8005/v1/speakers/Pat # remove
```

Tunable env vars:

| Variable | Default | Notes |
|---|---|---|
| `SPEAKER_MATCH_THRESHOLD` | `0.5` | Higher = stricter (fewer false matches, more `SPEAKER_XX`) |
| `MIN_ENROLL_SEG_SEC` | `1.0` | Minimum segment duration to attempt voiceprint matching |
| `EMBEDDING_MODEL` | `pyannote/embedding` | Override if you've enrolled with a different model |
| `VOICEPRINTS_PATH` | `/root/.cache/voiceprints.json` | Lives in the persistent model-cache volume |

You can re-enroll the same name multiple times — additional samples accumulate and improve match robustness.

## Troubleshooting

- **`HF_TOKEN not set`** — token missing from `.env` or env not picked up. `docker compose config` to verify it's in the rendered service env.
- **`Pipeline.from_pretrained returned None`** — token is set but you haven't accepted the pyannote license. Visit the model pages above and click Agree.
- **CUDA driver too old** — `nvidia-smi` reports `CUDA Version: 12.2` or lower. Upgrade host driver to 565+ (`sudo apt install nvidia-driver-590` and reboot).
- **`Resource temporarily unavailable` on `/dev/shm`** — already mitigated by `shm_size: 2gb` in compose.
