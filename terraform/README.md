# Pulse infrastructure

Phase 5 of `docs/roadmap.md` built the infrastructure shell - networking, an
empty ECS cluster, an ALB with no live targets, ECR repositories with nothing
pushed to them, IAM roles with nothing assuming them. Phase 6 (this state)
pushes images, and runs `api`/`scheduler`/`checker` on top of that shell as
ECS Fargate services, with the database credentials Secrets Manager already
held from Phase 5 wired into their task definitions.

```
terraform/
├── bootstrap/           # one-time: the S3 bucket + DynamoDB table for remote state
├── modules/              # vpc, ecr, alb, security_groups, ecs_cluster, ecs_service,
│                          # iam, rds, secrets
└── environments/
    ├── dev/              # single NAT gateway, single-AZ db.t4g.micro, 1 task/service
    └── prod/              # NAT gateway per AZ, multi-AZ db.t4g.small, 2 api/checker tasks
```

## First time in a new AWS account

1. Bootstrap the state backend (applies with local state - there's nothing to
   point it at yet):

   ```bash
   cd terraform/bootstrap
   terraform init
   terraform apply
   ```

   Note the `state_bucket` and `lock_table` outputs.

2. For each environment, copy `backend.hcl.example` to `backend.hcl` and fill
   in those two values (`backend.hcl` is gitignored - it's account-specific).

3. Every apply needs an `image_tag` (see below) and `scripts/push_images.sh`
   needs the ECR repositories to already exist to push into - so a brand new
   environment's very first apply only targets `module.ecr`, using any
   placeholder tag (nothing reads it yet):

   ```bash
   cd terraform/environments/dev   # or prod
   terraform init -backend-config=backend.hcl
   terraform apply -target=module.ecr -var image_tag=bootstrap
   ```

   From here on, `ecr_repository_urls` is in state and the normal flow below
   applies - this step never needs repeating.

## Applying an environment

Every apply needs an `image_tag` - ECR repositories are `IMMUTABLE`, so
there's no `latest` to float; each deploy is pinned to the exact image it
runs. Build and push one first (needs a clean git tree - see the script):

```bash
./scripts/push_images.sh dev   # or prod - builds api/scheduler/checker, tags
                                # with the current git commit, pushes to ECR
```

Then apply with that tag:

```bash
cd terraform/environments/dev   # or prod
terraform init -backend-config=backend.hcl
terraform plan  -var image_tag=<tag printed above>
terraform apply -var image_tag=<tag printed above>
```

`prod` uses the same modules with different sizing (see `main.tf`) - there is
no copy-pasted module code to drift between the two.

## Secrets

The RDS master password is generated and rotated by AWS itself
(`manage_master_user_password` on `modules/rds`) - Terraform never sees it as
plaintext. The one secret Terraform *can't* generate is the Slack webhook URL
(`modules/secrets` creates the secret with a placeholder value, so checker
has something resolvable to start with instead of failing to launch - alert
delivery just fails and logs a warning per attempt, same as any other Slack
outage, until the real value is set); set it once per environment after the
first apply:

```bash
aws secretsmanager put-secret-value \
  --secret-id "$(terraform -chdir=terraform/environments/dev output -raw slack_webhook_secret_arn)" \
  --secret-string 'https://hooks.slack.com/services/...'
```

The checker service picks up a changed value on its next task restart (ECS
resolves `secrets` values at task start, not continuously).

## Observability (Phase 8)

`modules/observability` is infra-level monitoring - CloudWatch alarms → SNS,
Logs Insights saved queries, and a RED-metrics dashboard - for Pulse's own
infrastructure (the ALB, ECS tasks, the database). It's a different layer
from `src/alerting` (Phase 2): that one watches whether a *monitored external
target* is up and posts to Slack; this one watches whether *Pulse itself* is
healthy.

- **Dashboard**: `<name>-red-metrics` in the CloudWatch console - Rate/Errors/
  Duration for `api` from the ALB (the only service with a client-facing HTTP
  entrypoint to measure that way), CPU/memory/running-task-count for
  `scheduler`/`checker` from Container Insights as the closest available
  proxy. `dashboard/` (Phase 4, the static status page) isn't part of this -
  it was never deployed to ECS in the first place (`var.services` only ever
  covers `api`/`scheduler`/`checker` - see `environments/dev/variables.tf`).
- **Alarms**: ALB 5xx rate/latency/unhealthy hosts, per-service ECS CPU/memory,
  RDS CPU/connections/free storage - all wired to one SNS topic. Subscribe an
  endpoint after apply (same "Terraform creates the topic, not who gets
  paged" reasoning as the Slack webhook above):

  ```bash
  aws sns subscribe \
    --topic-arn "$(terraform -chdir=terraform/environments/dev output -raw observability_sns_topic_arn)" \
    --protocol email --notification-endpoint you@example.com
  ```

- **X-Ray tracing**: `enable_xray = true` on each `ecs_service_*` module adds
  an X-Ray daemon sidecar to that task and sets `XRAY_ENABLED=true` on the
  app container (`src/common/tracing.py` patches `psycopg2`/`httpx` and
  records a segment per api/checker request, and per scheduler dispatch).
  Traces show up in the X-Ray console once real traffic flows through.
- **Logs Insights**: saved queries under `<name>/<service>/errors` (and
  `<name>/all-services/errors`) in CloudWatch Logs Insights - "Saved queries"
  in the console, no need to write the filter each time during an incident.

None of this has been run against real AWS from this session - no
credentials/network here (see the main repo README) - so treat it as built
and validated (`terraform validate`, not `plan`/`apply`), not yet exercised.

## SLO dashboard (Phase 11)

Grafana runs as a fourth ECS service (`module.ecs_service_grafana`),
sharing the existing ALB instead of getting its own - reachable at
`<alb_dns_name>/grafana/` (the `grafana_url` output). Its one dashboard
("Pulse - SLO Burn Rate") is provisioned from `docker/grafana/dashboards/`,
not clicked together in the UI - the exact same error-budget math as Phase
3's `src/api/queries.py`, run as raw SQL directly against production
`monitors`/`check_results`.

`docker compose up grafana` (`docker/docker-compose.yml`) runs this whole
image - build, entrypoint, provisioning, and all three panels' queries -
against a real local Postgres, which is how the SQL, the datasource config,
and the dashboard JSON were actually verified during development (through
Grafana's own query API, not just read for syntax). Two real bugs only
showed up this way and wouldn't have been caught by reading the Dockerfile:
the base image's `grafana` user's group is `root`, not a group literally
named `grafana` (`chown grafana:grafana` fails outright); and Grafana's
Postgres datasource only accepts `disable`/`require`/`verify-ca`/
`verify-full` for `sslmode`, not libpq's usual `prefer` - `DB_SSLMODE`
(default `require`, overridden to `disable` for local's plain
`postgres:16-alpine`) exists because of that.

A few things worth knowing before pointing this at a real environment:

- **Default login is `admin`/`admin`** - Grafana forces a password change on
  first login, but there's no SSO/real auth provider wired up here. Fine for
  a solo portfolio deployment, not for anything with more than one user.
- **Grafana's own state doesn't persist.** It uses its default embedded
  SQLite database for everything *except* the provisioned dashboard (users,
  sessions, any panel someone builds by hand in the UI) - that file lives on
  the Fargate task's ephemeral filesystem, gone on the next deploy or task
  replacement. The one dashboard this phase actually delivers survives that
  because it's provisioned from the image on every container start, not
  because Grafana persisted it. A real persistent setup would put Grafana's
  own state in Postgres too (`GF_DATABASE_TYPE=postgres` against a second
  database on the same RDS instance) - not built here.
- **One task, even in prod** - see the comment next to
  `module.ecs_service_grafana` in `environments/prod/main.tf` for why two
  replicas would actually be worse, not more resilient, given the state
  story above.
- The ALB path-based routing rule, and RDS's SSL behavior specifically
  (`DB_SSLMODE` defaults to `require`, untested against a real RDS instance -
  only against local plain Postgres), are the two pieces of this phase not
  exercised from this session - no AWS credentials/network here (see the
  main repo README).
