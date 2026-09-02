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
