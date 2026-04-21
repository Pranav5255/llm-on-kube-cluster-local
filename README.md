# OSS LLM on Kubernetes + Grafana

- **llmfit** → model choice documented in `data/MODEL_CHOICE.md`
- **Ollama** + **phi3:mini** in cluster
- **Chat UI** (FastAPI) + **kube-prometheus-stack** (optional)

## Quick start

**Note:** On Docker 29+, `kind load` for `ollama/ollama` can fail (`ctr: content digest … not found`). This repo **does not** load Ollama into kind; the cluster **pulls** `ollama/ollama:latest` from Docker Hub (`imagePullPolicy: Always`).

```bash
cd ~/oss-llm-k8s-demo
chmod +x scripts/*.sh
./scripts/install-tools.sh
export PATH="$(pwd)/bin:$PATH"
./scripts/cluster-up.sh
```

- **Chat UI:** http://127.0.0.1:8081  
- **Ollama API:** http://127.0.0.1:8080  

`cluster-up.sh` does **not** install Grafana; run **`./scripts/install-monitoring.sh`** afterward (see **Monitoring** below).

**All-in-one (after host GPU prep):** with `PATH` set as above, **`USE_GPU=1 ./scripts/setup-full-stack.sh`** runs `cluster-up.sh`, **`install-monitoring.sh`**, and **`install-gpu-observability.sh`** (DCGM exporter + NVIDIA GPU dashboard in Grafana). CPU-only: `USE_GPU=0 ./scripts/setup-full-stack.sh`.

## GPU (optional — NVIDIA)

Ollama defaults to **CPU** in Kind because node containers do not see your GPU until Docker + the toolkit are configured and the cluster is created with a **GPU Kind config**.

1. **Host prerequisites** — proprietary **NVIDIA driver** (`nvidia-smi` works).

2. **Install NVIDIA Container Toolkit** (provides `nvidia-ctk`). On Debian/Ubuntu:

```bash
chmod +x scripts/*.sh
./scripts/install-nvidia-container-toolkit-deb.sh
```

Other distros: [NVIDIA install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

3. **Configure Docker for GPU + CDI** (one-time; uses `sudo`, sets **nvidia** as Docker’s default runtime):

```bash
./scripts/setup-gpu-kind-host.sh
```

Use `./scripts/setup-gpu-kind-host.sh --print-only` to see the commands without running them.

4. **Create the cluster with GPU mounts** — `USE_GPU=1` makes `cluster-up.sh` use **`k8s/kind-cluster-gpu.yaml`**, which adds the NVIDIA **`extraMounts`** on the control-plane node. **Delete and recreate** the cluster after Docker/toolkit changes if it already existed (`kind delete cluster --name oss-llm`).

5. **Deploy** (device plugin + Ollama with `nvidia.com/gpu: 1`):

```bash
export PATH="$(pwd)/bin:$PATH"
USE_GPU=1 ./scripts/cluster-up.sh
```

Manifests: `k8s/base/ollama.yaml` (CPU) vs `k8s/overlays/gpu` (adds GPU requests/limits). Advanced multi-GPU layouts: **[nvkind](https://github.com/NVIDIA/nvkind)**.

6. **Verify** — `kubectl describe node` → **allocatable** `nvidia.com/gpu`; `kubectl logs -n llm deploy/ollama` should show GPU/CUDA, not CPU-only inference.

If the Ollama pod stays **Pending** with **Insufficient nvidia.com/gpu**, the Kind node still has no GPU: re-check steps **2–4** (toolkit, `setup-gpu-kind-host.sh`, then recreate the cluster). **`cluster-up.sh`** fails fast (~90s) if no GPU is advertised when `USE_GPU=1`.

**No `nvidia.com/gpu` even though the host smoke test passed?** The device plugin Helm chart schedules only on nodes with NFD labels (e.g. `pci-10de`). Plain Kind has none, so the DaemonSet could schedule **zero** pods. **`install-nvidia-device-plugin.sh`** labels nodes first so the plugin can run; upgrade/re-run it if you installed the chart before that logic existed (`helm uninstall -n nvidia nvidia-device-plugin`, then `USE_GPU=1 ./scripts/cluster-up.sh` or run the install script again).

**Device plugin `CrashLoopBackOff`?** The default container `securityContext` is often too strict for NVML inside Kind. The repo ships **`helm/values-nvidia-device-plugin-kind.yaml`** (`privileged: true`, `deviceDiscoveryStrategy: nvml`). Re-apply: `helm upgrade -n nvidia nvidia-device-plugin nvdp/nvidia-device-plugin -f helm/values-nvidia-device-plugin-kind.yaml` (or run **`./scripts/install-nvidia-device-plugin.sh`**). For logs: **`./scripts/diagnose-gpu-kind.sh`** — if `nvidia-smi` fails *inside* the Kind node container, the cluster still cannot see GPUs (driver/CDI inside the node).

## Load the model (weights into the cluster)

The Ollama `Deployment` runs `ollama pull phi3:mini` on startup (`OLLAMA_MODEL`). If the UI answers but chat errors (unknown model), or you want another tag, pull explicitly:

```bash
chmod +x scripts/pull-model.sh
./scripts/pull-model.sh              # default phi3:mini
./scripts/pull-model.sh mistral:7b   # optional: different Ollama tag
```

Or by hand:

```bash
kubectl exec -n llm deploy/ollama -- ollama pull phi3:mini
kubectl exec -n llm deploy/ollama -- ollama list
```

From the host (with NodePort **8080** mapped):

```bash
curl -s http://127.0.0.1:8080/api/pull -d '{"name":"phi3:mini"}'
```

Weights are stored on the **`ollama-data` PVC** (`/root/.ollama` in the pod), so they survive pod restarts.

## Monitoring (Grafana + cluster metrics)

The stack is **kube-prometheus-stack** (Prometheus, Grafana, kube-state-metrics, node-exporter). Config lives in `helm/values-kps.yaml` (Grafana admin password, Grafana **NodePort 32000** inside the cluster).

### Install

```bash
./scripts/install-monitoring.sh
```

Wait until pods are ready: `kubectl get pods -n monitoring`

### Open Grafana

**Option A — fixed URL (Kind only, after cluster was created with `k8s/kind-cluster.yaml`)**

- Map **host `127.0.0.1:3333`** → node NodePort **32000** (see `kind-cluster.yaml`).
- If the cluster was created **before** this mapping existed, run **`kind delete cluster --name oss-llm`** and `./scripts/cluster-up.sh` again (or use Option B).

**Option B — port-forward (works on any cluster)**

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3333:80
```

Then open **http://127.0.0.1:3333**

### Login

- **User:** `admin`
- **Password:** value of `grafana.adminPassword` in `helm/values-kps.yaml` (default **`changeme`**)

### Dashboards to show (take-home / video)

Built-in folders from kube-prometheus-stack; good starting points:

- **Dashboards → Browse** → folder **Kubernetes / Compute Resources** → e.g. **Cluster**, **Namespace (Pods)**, **Node (Pods)**
- **Node Exporter / Nodes** for per-node CPU, memory, disk
- **Kubernetes / Views** → **Global** for a high-level cluster view

These use metrics from your Kind node, `kube-state-metrics`, and the workloads in `llm` + `monitoring` namespaces—no extra wiring beyond running `install-monitoring.sh`.

### GPU metrics in Grafana (NVIDIA)

**Requires** the same host + Kind GPU setup as **GPU (optional — NVIDIA)** above.

**Definitive approach (Kind):** do **not** rely on an in-cluster DCGM DaemonSet. On Kind it often fails with **NVML `ERROR_LIBRARY_NOT_FOUND`** or crashes (**SIGSEGV**) when host/container libraries are mixed. Instead:

1. **`install-monitoring.sh`** merges **`helm/values-kps-dcgm-host.yaml`**, which points Prometheus at a default host address (**`172.17.0.1:9400`** — common **docker0** gateway; host-side DCGM listens on the host’s `9400`).
2. **`USE_GPU=1 ./scripts/install-gpu-observability.sh`** starts **DCGM in Docker on the host** (`scripts/run-dcgm-host.sh`), **re-applies** kube-prometheus-stack after **probing** which host IP is reachable from the Kind node (**`172.17.0.1`**, **`172.18.0.1`**, then the node’s default gateway — order matters), and loads the official **NVIDIA DCGM Exporter** Grafana dashboard (ConfigMap). Override with **`DCGM_SCRAPE_HOST`** if needed.

```bash
export PATH="$(pwd)/bin:$PATH"
./scripts/install-monitoring.sh          # includes DCGM scrape config
USE_GPU=1 ./scripts/install-gpu-observability.sh
```

**Checks:**

- Host: `curl -s http://127.0.0.1:9400/metrics | head` should show `DCGM_FI_` lines.
- Prometheus UI → **Status → Targets** → **`dcgm-host`** should be **UP**.
- Grafana → **NVIDIA DCGM Exporter Dashboard** (refresh after a minute or two).

**If Grafana still shows “No data” or the target is DOWN:** Prometheus may be scraping the wrong host IP. The Kind node’s **default gateway is not always** the address that reaches **host-published** ports. Run **`./scripts/diagnose-dcgm-observability.sh`** and check which `wget` from the Prometheus pod succeeds; then set **`DCGM_SCRAPE_HOST`** if the probe script cannot fix it:

```bash
export DCGM_SCRAPE_HOST=172.17.0.1   # or 172.18.0.1 — whichever works from your cluster
USE_GPU=1 ./scripts/install-gpu-observability.sh
```

You can also edit **`helm/values-kps-dcgm-host.yaml`** and run **`./scripts/install-monitoring.sh`** again.

**Optional:** `helm/values-dcgm-exporter.yaml` documents an **in-cluster** Helm install only for environments where DCGM works inside Kubernetes (e.g. some cloud GPU nodes); it is **not** the default for Kind.

## Benchmark

Compares **local Ollama** vs **Google Gemini** (OpenAI-compatible API). Create a key in [Google AI Studio](https://aistudio.google.com/apikey) (free tier).

```bash
export OSS_URL=http://127.0.0.1:8080
export GEMINI_API_KEY="your-key"   # or GOOGLE_API_KEY
# Optional: COMMERCIAL_MODEL=gemini-2.0-flash  COMMERCIAL_URL=...
python3 benchmark/run_benchmark.py
```

Writes `benchmark/benchmark-results.csv`. If `GEMINI_API_KEY` is unset, Gemini columns are marked `skipped`.

## Teardown

```bash
kind delete cluster --name oss-llm
```
