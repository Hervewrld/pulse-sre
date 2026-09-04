# Disaster recovery - RTO/RPO

Phase 10 of `docs/roadmap.md`. One page, per failure scenario the system is
actually built to survive - not an aspirational list. "Proof" means one of
`scripts/chaos/`'s drills, run and written up in `docs/postmortems/`, not
just this document existing. Three of the drills cited below
(`kill-database.sh`, `bad-deploy.sh`, `kill-service.sh`) come from Phase 9
([PR #11](https://github.com/Hervewrld/pulse-sre/pull/11), not yet merged as
of this doc) - only `az-failure-drill.sh` ships in this same PR.

| Scenario | RTO (target) | RPO (target) | How it's actually met | Proof |
| --- | --- | --- | --- | --- |
| One AZ down (prod) | < 5 min, no manual step | 0 (no data touched) | `api`/`checker` run 2 tasks across 2 AZs (`desired_count = 2`, `environments/prod/main.tf`); RDS is Multi-AZ (`multi_az = true`) with automatic failover; ALB only routes to healthy targets | `scripts/chaos/az-failure-drill.sh` |
| RDS instance failure (prod) | < 2 min (Multi-AZ failover time) | 0 - synchronous replication to the standby, no committed transaction is lost | `multi_az = true` gives a synchronous standby in the second AZ; RDS fails over to it automatically | `scripts/chaos/kill-database.sh prod` (Phase 9) |
| RDS instance failure (dev) | Manual - restore from the most recent automated backup | Up to 24h (last automated backup - dev takes daily snapshots, no standby) | `backup_retention_days` (7 in dev) plus point-in-time recovery within that window | `scripts/chaos/kill-database.sh dev` (Phase 9; reboot, not a real failure - dev has no standby to fail over to) |
| Bad deploy (either env) | < 10 min, automatic | 0 - no data involved | `deployment_circuit_breaker` + `wait_for_steady_state` (`modules/ecs_service`) roll ECS back on their own; `.github/workflows/deploy.yml`'s post-apply image verification and smoke test catch what the circuit breaker doesn't - all from Phase 7 ([PR #9](https://github.com/Hervewrld/pulse-sre/pull/9), not yet merged as of this doc) | `scripts/chaos/bad-deploy.sh` (Phase 9) |
| One ECS service fully down | < 2 min (ECS reschedules onto healthy capacity) | 0 | ECS's own service scheduler restarts failed/stopped tasks against `desired_count` automatically | `scripts/chaos/kill-service.sh` (Phase 9) |
| Full region loss | Not covered - no DR region | N/A | Out of scope by design (see below) | - |
| Accidental `terraform destroy` / state corruption | Hours, manual - recreate from `terraform apply` (VPC, ECS, ALB) + restore RDS from the latest automated snapshot | Up to the last automated RDS backup (see above) | Remote state (S3 + DynamoDB lock, `terraform/bootstrap`) survives independently of the environment it describes; `deletion_protection = true` on prod's RDS instance blocks the easy version of this entirely | Not drilled - destructive by nature, no safe way to rehearse against a real environment |

## What's explicitly out of scope, and why

**No second region.** A single-region, Multi-AZ design is the right tradeoff
for this project's actual risk profile (a portfolio monitoring tool, not a
system where an hour of downtime costs real money) - a second region roughly
doubles infrastructure cost and complexity (cross-region RDS replication or
a second database entirely, Route 53 failover, cross-region ECR replication)
for a failure mode (a whole AWS region down) that's far rarer than an AZ
outage. If the risk profile changed, active-passive with RDS read replica
promotion would be the next step - not built here.

**No backup restore drill (yet).** The failure scenarios above that end in
"restore from backup" have not actually been drilled - only the ones with a
`scripts/chaos/` script have real proof next to them. Restoring dev's RDS
instance from an automated snapshot to a fresh instance and confirming data
integrity is the natural next addition to `scripts/chaos/` once this has
been run against a real environment.

## Secrets rotation

The RDS master password rotates automatically every
`password_rotation_days` (default 30, `terraform/modules/rds`) via Secrets
Manager's built-in RDS rotation - no custom Lambda to maintain. Rotation
changes the password in the database immediately, but `api`/`scheduler`/
`checker` only read it once, at task start - a rotation firing needs a
`terraform apply` (or `aws ecs update-service --force-new-deployment`)
afterward to get already-running tasks onto the new value, or there's a
window where they're using a password that no longer works. This is a real
operational gap, not a hidden one: the fix is either accepting that manual
step, or moving rotation onto the same schedule as deploys eventually (not
built here).
