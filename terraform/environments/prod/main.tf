locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source = "../../modules/vpc"

  name = var.name
  azs  = local.azs
  # Prod: one NAT gateway per AZ, so a NAT/AZ failure only takes out that
  # AZ's egress, not the whole environment's.
  single_nat_gateway = false
}

module "ecr" {
  source = "../../modules/ecr"

  name             = var.name
  repository_names = var.services
}

module "alb" {
  source = "../../modules/alb"

  name              = var.name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  target_port       = var.api_container_port
}

module "security_groups" {
  source = "../../modules/security_groups"

  name                   = var.name
  vpc_id                 = module.vpc.vpc_id
  alb_security_group_id  = module.alb.alb_security_group_id
  api_container_port     = var.api_container_port
  checker_container_port = var.checker_container_port
}

module "ecs_cluster" {
  source = "../../modules/ecs_cluster"

  name   = var.name
  vpc_id = module.vpc.vpc_id
}

module "iam" {
  source = "../../modules/iam"

  name                = var.name
  services            = var.services
  ecr_repository_arns = module.ecr.repository_arns
}

module "rds" {
  source = "../../modules/rds"

  name               = var.name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security_groups.db_security_group_id

  instance_class        = "db.t4g.small"
  allocated_storage_gb  = 50
  multi_az              = true
  backup_retention_days = 14
  deletion_protection   = true
}
