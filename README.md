# ObsForge

Prometheus HA + Thanos  metric pipeline. Two Prometheus replicas scrape services,
Thanos ships sealed 2h blocks to S3/gcs, and a single Grafana endpoint queries years of data
with HA deduplication baked in.

Built for AWS EKS + S3. Only the bucket config changes for GCP or Azure — see platform notes.

---

## Stack

| Component             | Role                                                    |
| --------------------- | ------------------------------------------------------- |
| Prometheus x2         | HA scraping, 2h local TSDB blocks                       |
| Thanos Sidecar        | Upload sealed blocks to S3, proxy live data             |
| Thanos Store Gateway  | Query cold blocks straight from S3                      |
| Thanos Querier        | Fan-out queries + deduplicate HA replica data           |
| Thanos Query Frontend | Result caching and query sharding                       |
| Thanos Compactor      | Merge small blocks, create downsampled copies           |
| Thanos Ruler          | Global alerting and recording rules (optional)          |
| Grafana               | Dashboards — single data source pointing at the Querier |

---

## Prerequisites

- Kubernetes 1.27+ (EKS tested)
- `kubectl` configured against cluster
- An S3 bucket nodes can write to
- `envsubst` on deployment machine (`apt install gettext-base` / `brew install gettext`)

---

## Quickstart

```sh
cp .env.example .env
# S3_BUCKET_NAME, AWS credentials (or configure IRSA), and GRAFANA_ADMIN_PASSWORD

./scripts/create-secrets.sh   # creates k8s Secrets + ConfigMap from .env
./scripts/deploy.sh           # applies all manifests in dependency order

kubectl get svc grafana -n monitoring  # grab the LoadBalancer hostname
```

Default login: `admin` / value of `GRAFANA_ADMIN_PASSWORD`.

---

## Local Dev

Full pipeline locally using MinIO as an S3 substitute. No cloud needed.

```sh
cp .env.example .env          # MinIO defaults already work as-is
docker compose up -d

# Grafana      → http://localhost:3000  (admin / admin)
# MinIO console → http://localhost:9001  (minioadmin / minioadmin)
```

---

## Platform Notes

** for AWS (EKS + S3).** Two things change per platform:

1. **Bucket config** — `config/thanos/bucket.yml.example` has commented blocks for GCS and Azure Blob.
2. **StorageClass** — `gp3` is set in both StatefulSet files. Change to:
   - GCP GKE -> `standard-rwo`
   - Azure AKS -> `managed-premium`

### EKS + IRSA (recommended over static credentials)

Annotate the `prometheus` ServiceAccount with your IAM role ARN and remove
`access_key` / `secret_key` from the bucket config. The annotation placeholder
is already in `k8s/prometheus/rbac.yml`.

---

## Retention

Configured in `.env`, applied by the Compactor.

| Resolution            | Default  |
| --------------------- | -------- |
| Raw (15–30s samples)  | 30 days  |
| 5-minute downsampled  | 90 days  |
| 1-hour downsampled    | 1 year   |

---

## Layout

```
config/
  prometheus/     Scrape config and alerting rules (used by docker-compose)
  thanos/         Bucket config templates
  grafana/        Datasource provisioning
k8s/
  prometheus/     StatefulSets, RBAC, ConfigMaps
  thanos/         Store Gateway, Querier, Query Frontend, Compactor, Ruler
  grafana/        Deployment and datasource provisioning
scripts/
  create-secrets.sh   Bootstraps Secrets and ConfigMap from .env
  deploy.sh           Ordered kubectl apply with readiness gates
  teardown.sh         Removes the full stack (S3 data is untouched)
docker-compose.yml    Full local stack with MinIO
```

---

## Gotchas

- **Compactor must be a singleton.** Two instances against the same bucket will corrupt block metadata.
- Mount a PVC for Prometheus WAL so pods survive restarts without losing up to 2h of unsent data.
- Store Gateway downloads index headers on startup — queries for cold data will be slow for a minute or two after restart. Pre-warm with a persistent volume.
- The Sidecar only uploads *sealed* blocks. The current open block (live data) is served directly by the Sidecar's StoreAPI, so the Querier fans out to three sources on every query.
- Query Frontend is optional but keeps Grafana dashboards fast under heavy load.
