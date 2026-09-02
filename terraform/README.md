# Pulse infrastructure

Phase 5 of `docs/roadmap.md` built the infrastructure shell - networking, an
empty ECS cluster, an ALB with no live targets, ECR repositories with nothing
pushed to them, IAM roles with nothing assuming them. Phase 6 runs
`api`/`scheduler`/`checker` on top of that shell as ECS Fargate services,
with the database credentials Secrets Manager already held from Phase 5
wired into their task definitions. Phase 7 (`../.github/workflows/`) is
built to call `terraform apply` from here on, once the one-time setup under
"CI/CD (Phase 7)" below has actually been done in this AWS account/repo -
until then, applying is still a manual `terraform apply` per the sections
above.

```
terraform/
├── bootstrap/           # one-time: state backend + the GitHub Actions OIDC role
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

## CI/CD (Phase 7)

`.github/workflows/deploy.yml` runs `terraform apply` for you on every push
to `main` - dev automatically, prod behind a manual approval gate - using
short-lived credentials from the `pulse-github-deploy` IAM role
(`bootstrap/github_oidc.tf`), not stored AWS keys. Nobody needs to run
`terraform apply` from a laptop once this is wired up (dev/prod first apply
above is the one exception - it has to exist before CI can update it).

One-time setup, after `terraform apply` in `bootstrap/` (which now also
creates the OIDC provider and deploy role):

1. Set these as **repository variables** (not secrets - none of them are
   sensitive), Settings > Secrets and variables > Actions > Variables:

   | Name | Value |
   | --- | --- |
   | `AWS_DEPLOY_ROLE_ARN` | bootstrap's `github_deploy_role_arn` output |
   | `TF_STATE_BUCKET` | bootstrap's `state_bucket` output |
   | `TF_LOCK_TABLE` | bootstrap's `lock_table` output |
   | `AWS_REGION` | `us-east-1` (or whatever `bootstrap`'s `region` output is) |

2. Create a `production` GitHub Environment (Settings > Environments > New
   environment) and add at least one required reviewer. That's the manual
   approval gate for prod - `deploy-prod` in the workflow just references
   `environment: production` and GitHub blocks the job until someone
   approves it there. Also set "Deployment branches and tags" on that same
   environment to only allow `main` - the OIDC trust policy's `sub` claim
   accepts anything tagged `environment:production` regardless of branch, so
   this branch restriction (not the trust policy) is what stops some other
   workflow/branch from ever reaching that gate in the first place.

`ci.yml` (lint/test/build/scan) needs none of this - it never touches AWS,
so it runs on every PR from a fork just as safely as one from this repo.
