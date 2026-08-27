locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source = "../../modules/vpc"

  name = var.name
  azs  = local.azs
  # Dev: one NAT gateway shared by both AZs. Cheaper; an AZ outage takes the
  # other AZ's egress down with it, which is an acceptable trade for dev.
  single_nat_gateway = true
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

  instance_class      = "db.t4g.micro"
  multi_az            = false
  deletion_protection = false
}
