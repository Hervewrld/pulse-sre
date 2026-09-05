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

- [x] **Phase 0 — Core app**: `src/api`, `src/scheduler`, `src/checker`, `tests/`
- [x] **Phase 1 — Time-series storage**: real uptime-% queries from check history
- [x] **Phase 2 — Alerting logic**: debounced alerts, Slack notification
- [x] **Phase 3 — SLO math**: error-budget burn-rate calculation
- [x] **Phase 4 — Dashboard**: `dashboard/`
- [x] **Phase 5 — AWS infra (Terraform)**: `terraform/`
- [x] **Phase 6 — Deploy to AWS**: ECS task defs, Secrets Manager
- [ ] **Phase 7 — CI/CD**: `.github/workflows/` (code complete - [PR #9](https://github.com/Hervewrld/pulse-sre/pull/9), not yet merged)
- [x] **Phase 8 — Observability**: CloudWatch alarms/SNS/dashboard, Logs Insights, X-Ray (`terraform/modules/observability`)
- [ ] **Phase 9 — Incident response**: `docs/postmortems/`, `scripts/chaos/` (drills built - [PR #11](https://github.com/Hervewrld/pulse-sre/pull/11), not yet merged; real postmortems still need writing after they're run)
- [ ] **Phase 10 — Security, DR, business continuity**: least-privilege IAM/SGs (already in place), optional HTTPS, secrets rotation, `docs/disaster-recovery.md`, AZ-failure drill ([PR #12](https://github.com/Hervewrld/pulse-sre/pull/12), not yet merged)
- [ ] **Phase 11 — SLO burn-rate dashboard (production)**: Grafana as a 4th ECS service sharing the ALB, one dashboard provisioned as code (`docker/grafana/`) running Phase 3's exact burn-rate math as SQL against production data ([PR #13](https://github.com/Hervewrld/pulse-sre/pull/13), not yet merged; tested end-to-end locally, not yet run against real AWS)
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
│   └── chaos/            # Phase 9/10 - deliberately break things, on purpose
├── docker/             # Dockerfiles + docker-compose
│   └── grafana/           # Phase 11 - Grafana image, SLO dashboard provisioned as code
├── dashboard/           # simple status page (Phase 4)
├── terraform/
│   ├── modules/
│   └── environments/    # dev / prod
├── k8s/                  # optional, Phase 12
├── .github/workflows/    # CI/CD
├── monitoring/           # unused - see below
└── docs/
    ├── roadmap.md          # full phase-by-phase plan
    ├── git-workflow.md
    └── postmortems/         # Phase 9 incident write-ups
```

`monitoring/` is a leftover from the original scaffold's plan to hand-write Grafana
JSON/Prometheus rules there - Phase 8 built infra-level monitoring (dashboard,
alarms, Logs Insights queries) as Terraform instead (`terraform/modules/observability`),
and Phase 11's actual Grafana dashboard is provisioned as code from `docker/grafana/`
instead, so there's nothing left for this directory to hold - see `terraform/README.md`
for both.
