# Postmortems

Phase 9 of `docs/roadmap.md`: deliberately break things, detect it via the
alerting/observability already built (Phase 2's Slack alerts, Phase 8's
CloudWatch alarms - not by watching a script's output), and write up what
actually happened.

## Running a drill

`scripts/chaos/` has three drills, each targeting a different failure mode
the roadmap calls out:

| Script | Simulates | Roadmap's phrasing |
| --- | --- | --- |
| `kill-database.sh <env>` | RDS failover (prod) / reboot (dev) | "kill ElastiCache/DB" - no ElastiCache in this stack, RDS is the equivalent |
| `bad-deploy.sh <env> <service>` | A broken image tag reaching ECS | "bad task definition" |
| `kill-service.sh <env> <service>` | Zero healthy targets behind the ALB | "throttle the ALB" - the closest safe, reproducible equivalent; see the script's own comment for why |

All three need AWS credentials with real access to that environment (the
`pulse-github-deploy` OIDC role from `terraform/bootstrap/github_oidc.tf`
works if you can assume it, or your own credentials) - they call the AWS CLI
directly, not through Terraform or CI. `prod` runs require typing the
environment name to confirm.

Before running one:

1. Make sure you're actually watching the detection surface first -
   CloudWatch alarms/dashboard (Phase 8), the SNS topic if you've subscribed
   to it, Slack if `SLACK_WEBHOOK_URL` is configured (app-level alerts only
   fire for monitored *targets*, not Pulse's own infra - see Phase 8's
   README section on the difference).
2. Run the script. It prints what to watch and does not tell you when to
   stop watching - that's the point of noticing recovery yourself instead of
   being told.
3. Once resolved, copy `TEMPLATE.md` to `<date>-<short-title>.md` and fill
   it in from what you actually observed - real timestamps from the alarm
   history and Logs Insights, not reconstructed from memory afterward.

## What's here

Real write-ups go directly in this directory once a drill (or a real
incident) has actually happened - `<date>-<short-title>.md`, e.g.
`2026-03-01-rds-failover.md`. None exist yet: this phase's Terraform/tooling
work happened in a sandboxed session with no AWS credentials or network
access (see the main repo README) - the drills above are built and ready to
run, but running them and writing up 2-3 real postmortems (this phase's
actual deliverable per the roadmap) is the next step against a live
deployment.
