# Pulse infrastructure

Phase 5 of `docs/roadmap.md`: the infrastructure shell an environment needs to
exist - networking, an empty ECS cluster, an ALB with no live targets yet, ECR
repositories with nothing pushed to them, IAM roles with nothing assuming them.
Phase 6 pushes images, writes ECS task definitions, and creates the ECS
services that actually run Pulse on top of this.

```
terraform/
├── bootstrap/          # one-time: the S3 bucket + DynamoDB table for remote state
├── modules/             # vpc, ecr, alb, security_groups, ecs_cluster, iam, rds
└── environments/
    ├── dev/             # single NAT gateway, single-AZ db.t4g.micro
    └── prod/             # NAT gateway per AZ, multi-AZ db.t4g.small
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

## Applying an environment

```bash
cd terraform/environments/dev   # or prod
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

`prod` uses the same modules with different sizing (see `main.tf`) - there is
no copy-pasted module code to drift between the two.
