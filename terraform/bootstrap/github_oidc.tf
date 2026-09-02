# Lets GitHub Actions (.github/workflows/deploy.yml) assume an AWS role using
# short-lived, workflow-scoped OIDC tokens instead of long-lived access keys
# stored as repo secrets - no static AWS credentials exist anywhere for CI.

# thumbprint_list wants the SHA1 fingerprint of the OIDC issuer's TLS certificate.
# Fetched live instead of hardcoded - GitHub has rotated this before, and a stale
# or mistyped value fails closed (AssumeRoleWithWebIdentity just stops working)
# rather than in any way that's obviously wrong at a glance.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Two allowed callers: the dev-deploy job (runs on every push to main) and
    # the prod-deploy job (gated behind the "production" GitHub Environment's
    # required reviewers - see deploy.yml). Nothing else - a workflow run from
    # a PR branch, or a fork, gets no token this role will accept.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.github_repo}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_assume.json
}

data "aws_caller_identity" "deploy" {}

# Scoped tightly wherever AWS supports resource-level ARNs (state backend,
# ECR, Secrets Manager, CloudWatch Logs, IAM roles this project itself owns).
# EC2/ELB/ECS/RDS/Cloud Map don't support that for most of the actions below
# (the same tradeoff terraform/modules/iam already documents for
# ecr:GetAuthorizationToken), so Resource has to stay "*" there - the action
# lists are the only lever left, and are each limited to exactly what this
# project's own modules call, not a blanket `service:*`.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "TerraformState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "TerraformLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.lock.arn]
  }

  statement {
    sid       = "Ecr"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:*:${data.aws_caller_identity.deploy.account_id}:repository/${var.project}-*/*"]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level scoping
  }

  statement {
    sid       = "SecretsManager"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.deploy.account_id}:secret:${var.project}-*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:*"]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.deploy.account_id}:log-group:/ecs/${var.project}-*"]
  }

  statement {
    sid = "IamForThisProjectsRoles"
    # Covers CreateRole/DeleteRole/GetRole/PutRolePolicy/DeleteRolePolicy/
    # TagRole/PassRole/etc. in one pattern - every one of those action names
    # contains "Role".
    actions   = ["iam:*Role*"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.deploy.account_id}:role/${var.project}-*"]
  }

  # VPC/EC2 networking (modules/vpc, modules/security_groups): almost none of
  # this supports resource-level ARNs at all (AWS requires Resource = "*" for
  # the create/describe calls below regardless of which VPC or SG they touch),
  # so the only lever available is limiting the action list itself to exactly
  # what those two modules' resource types call.
  statement {
    sid = "Ec2Networking"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:ModifyVpcAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DescribeInternetGateways",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DescribeAddresses", "ec2:DescribeAddressesAttribute",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway", "ec2:DescribeNatGateways",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules", "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "Elb"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes", "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes", "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags", "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "Ecs"
    actions = [
      "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters", "ecs:PutClusterCapacityProviders",
      "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition",
      "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService", "ecs:DescribeServices",
      "ecs:ListTasks", "ecs:DescribeTasks",
      "ecs:TagResource", "ecs:UntagResource", "ecs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid = "Rds"
    actions = [
      "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:DescribeDBInstances", "rds:ModifyDBInstance",
      "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup", "rds:DescribeDBSubnetGroups",
      "rds:AddTagsToResource", "rds:RemoveTagsFromResource", "rds:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid = "CloudMap"
    actions = [
      "servicediscovery:CreatePrivateDnsNamespace", "servicediscovery:DeleteNamespace",
      "servicediscovery:GetNamespace", "servicediscovery:ListNamespaces", "servicediscovery:GetOperation",
      "servicediscovery:CreateService", "servicediscovery:DeleteService", "servicediscovery:GetService", "servicediscovery:ListServices",
      "servicediscovery:TagResource", "servicediscovery:UntagResource", "servicediscovery:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ProviderInit"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.project}-github-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
