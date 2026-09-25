# AI & automation stack (`ai-tools`): n8n, Ollama, Stirling-PDF

> Compose project `~/docker/ai-tools` · network `server-net` · last verified 2026-09-25.
> **In one line:** n8n runs automations, Ollama runs a local LLM (currently on CPU because the GPU driver is too old), and Stirling-PDF is a web PDF toolbox.

## Containers

| Container | Image | Ports | Memory cap | Data lives in | Notes |
|---|---|---|---|---|---|
| n8n | `docker.n8n.io/n8nio/n8n:latest` | **`0.0.0.0:5678`** | 1 GiB | `/docker/appdata/n8n → /home/node/.n8n` (9 MB) | Owner account set up (login required). Served at `https://n8n.example.com` (tailnet-only). |
| ollama | `ollama/ollama:latest` | 11434 | **none** | `/docker/appdata/ollama` (4.9 GB) | Model `qwen3:8b` (5.2 GB). `OLLAMA_KEEP_ALIVE=0`. **No authentication** on its API. |
| stirling-pdf | `frooodle/s-pdf:latest` | 8081→8080 | 1 GiB | `/mnt/tank/stirling-pdf/extraConfigs → /configs` | **No login** (`DOCKER_ENABLE_SECURITY=false`). Served at `https://pdf.example.com` (tailnet-only). |

**Who can reach it:** tailnet (by domain name) and LAN (by port). Not the internet.

## n8n

**Why notifications stopped (found 2026-09-25):** the only workflow is *Gmail Trigger → Ollama (summarize) → Discord*. Since ~2026-09-19 the Gmail trigger fails with "Access could not be refreshed … refresh token expired". No emails get in, so Ollama and Discord are never called. Ollama itself is fine; it responds, it's just idle. Fix: in n8n → Credentials → Gmail → **Reconnect**. If the Google Cloud OAuth app is in *Testing* mode, Google expires its tokens every 7 days; set it to *In production* (OAuth consent screen → Publish app) so it stops breaking weekly. Run history: 26 successes, 96 errors.

- Backups: **none.** Everything is in `/docker/appdata/n8n`: `database.sqlite` holds the workflows and `config` holds the encryption key. Without that key, saved credentials can't be decrypted after a restore.
- The port binding regressed from loopback (`127.0.0.1:5678`) to all interfaces. nginx reaches it through the host either way, so set it back to `"127.0.0.1:5678:5678"`.
- Memory: the 1 GiB cap keeps a runaway workflow from starving the game servers. Add `NODE_OPTIONS=--max-old-space-size=768` so Node cleans up memory before the cap kills it.

## Ollama: why it's slow right now

| | Intended | Actual |
|---|---|---|
| Runs on | GPU (RTX 2060 SUPER, 8 GB VRAM) | **CPU**: the log says `NVIDIA driver too old … driver=535 required_driver="550 or newer"` |
| Memory limit | strict cap | none |
| Idle | — | model unloaded after every request (`OLLAMA_KEEP_ALIVE=0`) |

An 8B model needs ~5–6 GB. On the GPU that fits in VRAM and barely touches RAM; on the CPU it has to load into a VM whose RAM and swap are already full. Fix it in this order:

1. Install NVIDIA driver 550+ in the VM (bookworm-backports or the NVIDIA CUDA repo), then reboot. The Proxmox host needs no driver, because the card is passed through.
2. Add `mem_limit: 3g` and `memswap_limit: 5g`, plus `OLLAMA_MAX_LOADED_MODELS=1` and `OLLAMA_NUM_PARALLEL=1`.
3. The same driver upgrade lets Immich's machine learning use the GPU too.

## Stirling-PDF: what the 7.6 GB really is

The earlier docs called the 7.6 GB under `/mnt/tank/stirling-pdf` OCR training data. It isn't: `trainingData` is empty. The space is **33 Java heap dumps (~248 MB each)** written 2026-09-12 → 09-14. Each dump means Stirling ran out of heap memory, crashed and restarted. The default heap is ~256 MiB (a quarter of the 1 GiB cap), and that proved too small. No new dumps have appeared since 2026-09-14.

| | Intended | Actual |
|---|---|---|
| Container limit | 512 MiB | 1 GiB |
| Java heap | `-Xms64m -Xmx256m` | image default (~256 MiB), heap dumps on crash |
| State | running | running, healthy, ~370 MiB |

Fix:

1. Delete `/mnt/tank/stirling-pdf/extraConfigs/heap_dumps/*.hprof` (frees 7.6 GB).
2. Set `JAVA_CUSTOM_OPTS=-Xms64m -Xmx512m -XX:-HeapDumpOnOutOfMemoryError`.
3. Keep the 1 GiB cap, which leaves room for LibreOffice/Tesseract.
4. Add `stop_grace_period: 30s`.

Because Stirling has no login, anyone on the tailnet or LAN can use it. That's fine while you're the only user.

## Backups

Only n8n matters here (see above). Ollama models and Stirling data can be downloaded again.
