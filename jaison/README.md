# jaison — AI box

LAN-only inference server. Runs the `jaison/llm/` router (`llm-swap` launching Strata, vLLM, and llama.cpp sibling containers) on 4× AMD Radeon AI Pro R9700; nothing here is on the public gateway. `jason-server` (the media box) keeps Traefik, quack, `llm-swap-media`, and the model archive, and reaches this box over the LAN (`192.168.50.202:11436`).

| Component | Part |
|-----------|------|
| CPU | AMD Threadripper 7960X (24c Zen 4, sTR5) |
| Board | ASUS Pro WS TRX50-SAGE WIFI A (CEB) — 3× PCIe 5.0 x16, 1× PCIe 4.0 x16, IPMI, 10GbE + 2.5GbE, Wi-Fi 7 |
| RAM | 128 GB DDR5-5600 ECC RDIMM (4× 32 GB, one per channel) |
| GPU | 4× R9700 (32 GB each) |
| Storage | 1 TB NVMe: OS + `/mnt/cache/huggingface` working set (~275 GB) |
| PSU | MSI MPG Ai1600TS 1600 W (ATX 3.1) |
| Cooler | be quiet! Silent Loop 3 360 (sTR5 bracket) |
| Case | Fractal Define 7 XL |
| OS | Ubuntu Server 26.04.1 LTS |

Setup: [`setup.md`](setup.md). Scripts: [`scripts/`](scripts/).

## How the two boxes fit together

- `jaison/llm/docker-compose.yml` runs here (`make up` from `jaison/llm/`), models on the local NVMe. Long-term model storage is the `media/models` ZFS dataset on the media box; copy to NVMe before serving, never run a model over NFS.
- The media box's `llm-swap-media` (`llm/llm-swap-media.yaml`) serves `clef` / `clef-flash` / `qwen3-omni-30b` locally on its RTX 3090 and peers to this box (`http://192.168.50.202:11436`) for every other model, including the CPU embedder `qwen3-embed`. Both Traefik's `/openai` route (`api/traefik/dynamic/llm.yml`) and quack talk to `llm-swap-media`.
- Firewall: SSH from LAN, 11436 and exporter ports (9100/9836/8082) from the media box, plus tailnet (`tailscale0`).
