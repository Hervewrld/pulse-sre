# Pulse

A self-built uptime & SLO monitoring platform — the kind of tool an SRE
operates every day, built from scratch to actually understand how it works.

Four services: `api` (register/query monitors), `scheduler` (decides what's
due for a check), `checker` (performs the check, horizontally scalable),
and alert evaluation logic living alongside them. Postgres for time-series
storage. Deployed to AWS via Terraform, with a full CI/CD and observability
stack around it.

Full phase-by-phase plan: see `docs/roadmap.md`.

## Phases

- [ ] **Phase 0 — Core app**: `src/api`, `src/scheduler`, `src/checker`, `tests/`
- [ ] **Phase 1 — Time-series storage**: real uptime-% queries from check history
- [ ] **Phase 2 — Alerting logic**: debounced alerts, Slack notification
- [ ] **Phase 3 — SLO math**: error-budget burn-rate calculation
- [ ] **Phase 4 — Dashboard**: `dashboard/`
- [ ] **Phase 5 — AWS infra (Terraform)**: `terraform/`
- [ ] **Phase 6 — Deploy to AWS**: ECS task defs, Secrets Manager
- [ ] **Phase 7 — CI/CD**: `.github/workflows/`
- [ ] **Phase 8 — Observability**: `monitoring/dashboards`, `monitoring/alerts`
- [ ] **Phase 9 — Incident response**: `docs/postmortems/`
- [ ] **Phase 10 — Security, DR, business continuity**
- [ ] **Phase 11 — SLO burn-rate dashboard (production)**
- [ ] **Phase 12 — Optional: Kubernetes**: `k8s/base`, `k8s/helm`

## Local development

```bash
./scripts/bootstrap.sh      # sets up venv, installs deps, runs tests
```

## Repo layout

```
pulse/
├── src/
│   ├── api/          # FastAPI - register/query monitors
│   ├── scheduler/    # decides which monitors are due for a check
│   ├── checker/       # performs HTTP checks, records results
│   └── common/         # shared code: db models, config, logging setup
├── tests/
├── scripts/            # bash automation
├── docker/             # Dockerfiles + docker-compose
├── dashboard/           # simple status page (Phase 4)
├── terraform/
│   ├── modules/
│   └── environments/    # dev / prod
├── k8s/                  # optional, Phase 12
├── .github/workflows/    # CI/CD
├── monitoring/
│   ├── dashboards/        # Grafana dashboard JSON
│   └── alerts/             # Prometheus/CloudWatch alert rules
└── docs/
    ├── roadmap.md          # full phase-by-phase plan
    ├── git-workflow.md
    └── postmortems/         # Phase 9 incident write-ups
```
