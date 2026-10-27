locals {
  name       = "${var.project}-${var.env}" # e.g. tritier-dev
  ssm_prefix = "${var.project}/${var.env}"
}

module "network" {
  source   = "../../modules/network"
  name     = local.name
  region   = var.region
  cidr     = var.vpc_cidr
  nat_mode = var.nat_mode
}

module "security" {
  source = "../../modules/security"
  name   = local.name
  vpc_id = module.network.vpc_id
}

module "data" {
  source        = "../../modules/data"
  name          = local.name
  ssm_prefix    = local.ssm_prefix
  db_subnet_ids = module.network.db_subnet_ids
  db_sg_id      = module.security.db_sg_id
  multi_az      = var.db_multi_az
}

module "app" {
  source                  = "../../modules/app"
  name                    = local.name
  ssm_prefix              = local.ssm_prefix
  vpc_id                  = module.network.vpc_id
  public_subnet_ids       = module.network.public_subnet_ids
  app_subnet_ids          = module.network.app_subnet_ids
  alb_sg_id               = module.security.alb_sg_id
  app_sg_id               = module.security.app_sg_id
  database_url_param_name = module.data.database_url_param_name
  initial_image           = var.initial_image
  min_size                = var.app_min_size
  max_size                = var.app_max_size
  certificate_arn         = var.certificate_arn
}

module "monitoring" {
  source                  = "../../modules/monitoring"
  name                    = local.name
  ssm_prefix              = local.ssm_prefix
  subnet_id               = module.network.app_subnet_ids[0]
  monitoring_sg_id        = module.security.monitoring_sg_id
  alb_arn_suffix          = module.app.alb_arn_suffix
  target_group_arn_suffix = module.app.target_group_arn_suffix
  db_identifier           = module.data.db_identifier
  asg_name                = module.app.asg_name
  alert_email             = var.alert_email
}
