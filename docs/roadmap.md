# Pulse — Master Roadmap

One project, one sequence, from local code to a production-grade AWS system
with full SRE practices around it. Each phase builds on the last — don't
skip ahead even if a later phase looks more interesting.

---

## JD coverage at a glance

| JD requirement | Phase(s) |
|---|---|
| Scripting (Python/Bash) | 0, throughout |
| Scalable cloud infrastructure on AWS | 5, 6 |
| Terraform / IaC | 5 |
| Automate provisioning & operational workflows | 5, 7 |
| CI/CD pipelines | 7 |
| Monitoring, logging, tracing, alerting | 3, 8 |
| Incident response, RCA, postmortems | 9 |
| Operational readiness / reliability collaboration | 9 (runbooks) |
| Security, DR, business continuity | 10 |
| Reduce operational overhead via automation | 5, 7 |
| SLOs / SLIs / Error budgets | 3, 11 |
| Linux administration & troubleshooting | throughout (local dev, containers, EC2/ECS) |
| Networking & cloud architecture | 5, 6 |
| Kubernetes (nice-to-have) | 12 (optional, last) |

---

## The sequence

### Phase 0 — Core app (local)
Build `api`, `scheduler`, `checker` running locally with Docker Compose.
Monitors can be registered, checks run on schedule, results get recorded.
**Output:** a working system on your laptop, with tests.

### Phase 1 — Time-series storage
Pick and justify a storage approach (Postgres, TimescaleDB, or similar).
Implement real uptime-% queries from raw check history.
**Output:** `GET /monitors/{id}/history` returns real historical data, not mocked.

### Phase 2 — Alerting logic
Debounced alert rules (e.g. 3 consecutive failures, not 1), a real
notification channel (Slack webhook is easiest), down/recovered events only
— no spam.
**Output:** killing a monitored target produces exactly one alert, and
exactly one recovery notification.

### Phase 3 — SLO math
Define an SLI (e.g. successful checks / total checks), set an SLO (e.g.
99.5% over 30 days), and implement error-budget burn-rate as a real
calculation from stored data.
**Output:** an endpoint or query that answers "how much error budget is left
this month" — this is the piece most candidates only describe rather than
build.

### Phase 4 — Dashboard
A simple status page showing all monitors, current status, uptime bar.
Good phase to lean on Claude Code for — it's UI, not core design.
**Output:** something you could screen-share in an interview.

*— Local system complete. Everything past this point is making it a real production service. —*

### Phase 5 — AWS infrastructure (Terraform)
VPC across 2 AZs, ECS Fargate cluster, ALB, ECR, IAM roles scoped per
service, remote state in S3 + DynamoDB lock table, `dev`/`prod` separation.
**Output:** `terraform apply` builds the entire environment from nothing.

### Phase 6 — Deploy Pulse onto it
Push images to ECR, write ECS task definitions, move secrets to Secrets
Manager, get `api`/`scheduler`/`checker` running as separate ECS services.
**Output:** Pulse reachable through a real ALB URL, monitoring real external
targets.

### Phase 7 — CI/CD pipeline
GitHub Actions: lint/test/build/scan on PR; on merge, deploy to ECS with a
manual approval gate for prod, automated smoke test, automatic rollback on
failure.
**Output:** a git push is the only manual step from code to production.

### Phase 8 — Observability
CloudWatch Logs + Insights queries, Prometheus/Grafana (or Amazon Managed
versions) scraping `/metrics`, X-Ray tracing across the four services,
CloudWatch Alarms → SNS for infra-level alerts (separate from Pulse's own
app-level alerting from Phase 2 — know the difference between the two
layers).
**Output:** one dashboard showing RED metrics across all four services.

### Phase 9 — Incident response & postmortems
Deliberately break things (kill ElastiCache/DB, bad task definition,
throttle the ALB). Detect via your own alerts, not because you caused it.
Write real postmortems into `docs/postmortems/`.
**Output:** 2–3 real incident write-ups — timeline, root cause, follow-ups.

### Phase 10 — Security, DR, business continuity
Least-privilege IAM, scoped security groups, Secrets Manager rotation, an
actual AZ-failure drill, a one-page RTO/RPO doc.
**Output:** proof (not just claim) that the system survives an AZ loss.

### Phase 11 — SLO burn-rate dashboard (production version)
Take the Phase 3 math and put it in Grafana against real production data —
now monitoring real external targets over real time, not local test data.
**Output:** the single dashboard you'd screen-share for "tell me about SLOs
you've implemented."

### Phase 12 — Optional: Kubernetes
Move from ECS to EKS, reusing patterns from order-service's Helm chart work.
Only after everything above is solid.
**Output:** the ability to compare ECS vs. Kubernetes intelligently in an interview.

---

## Suggested pacing

| Phase | Focus | Time (part-time) |
|---|---|---|
| 0–4 | Core app + dashboard | 3–4 weeks |
| 5–6 | AWS infra + deploy | 2–3 weeks |
| 7 | CI/CD | 1–2 weeks |
| 8 | Observability | 2 weeks |
| 9 | Incident response | ongoing |
| 10 | Security/DR | 1–2 weeks |
| 11 | SLO dashboard | 1 week |
| 12 | Kubernetes (optional) | 2 weeks |

**Total: roughly 3 months part-time for a complete, JD-matched project.**

---

## Before you create the repo

Decide these three things now — they shape the repo structure from day one:

1. **Language/framework for `api`/`scheduler`/`checker`**: Python/FastAPI (consistent with order-service) is the reasonable default unless you want the "nice to have" Go/Java experience from the JD.
2. **Time-series store**: Postgres is the safe, well-understood default; TimescaleDB or Timestream if you want that specific experience on your resume.
3. **Monorepo vs. multi-repo**: one repo with `api/`, `scheduler/`, `checker/` as subfolders (recommended — easier to manage solo) vs. separate repos per service (more realistic for a large org, more overhead for one person).
