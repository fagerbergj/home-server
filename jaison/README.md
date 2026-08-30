# jaison — AI box

LAN-only inference server. Runs the `llm/` stack (llama-swap on the Vulkan
llama.cpp image) on 2× AMD Radeon AI Pro R9700; nothing here is on the public
gateway. `jason-server` (the media box) keeps Traefik, quack, and the model
archive, and reaches this box over the LAN by hostname.

| Component | Part |
|-----------|------|
| CPU | AMD Threadripper 7960X (24c Zen 4, sTR5) |
| Board | ASUS Pro WS TRX50-SAGE WIFI A (CEB) — 3× PCIe 5.0 x16, 1× PCIe 4.0 x16, IPMI, 10GbE + 2.5GbE, Wi-Fi 7 |
| RAM | 128 GB DDR5-5600 ECC RDIMM (4× 32 GB, one per channel) |
| GPU | 2× R9700 (32 GB each) in slots 1 and 4; slot 7 free for a third |
| Storage | 1 TB NVMe: OS + `/mnt/cache/huggingface` working set (~275 GB) |
| PSU | MSI MPG Ai1600TS 1600 W (ATX 3.1) |
| Cooler | be quiet! Silent Loop 3 360 (sTR5 bracket) |
| Case | Fractal Define 7 XL |
| OS | Ubuntu Server 26.04.1 LTS |

Setup: [`setup.md`](setup.md). Scripts: [`scripts/`](scripts/).

## How the two boxes fit together

- `llm/docker-compose.yml` runs here (`make swap-up` from `llm/`), models on the
  local NVMe. Long-term model storage is the `media/models` ZFS dataset on the
  media box; copy to NVMe before serving, never run a model over NFS.
- The media box's Traefik forwards `api.jasonfagerberg.duckdns.org/openai` to
  `http://jaison:11436` (file-provider route), quack points
  `QUACK_LLM_ENDPOINT` at the same address, and this box's `llm-swap.yaml` can
  declare the media box's 3090 as a llama-swap `peer` for the embedder.
- Firewall: only 22 and 11436, and 11436 only from the media box.
