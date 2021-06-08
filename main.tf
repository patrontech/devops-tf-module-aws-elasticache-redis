locals {
  port                    = var.port == "" ? "6379" : var.port
  cache_subnet_group_name = var.cache_subnet_group_name == "" ? join("", aws_elasticache_subnet_group.this.*.name) : var.elasticache_subnet_group_name
  cache_security_group_id = join("", aws_security_group.this.*.id)

  name = "${var.name}-elasticache"
}

resource "aws_elasticache_subnet_group" "this" {
  count = var.create_cluster && var.cache_subnet_group_name == "" ? 1 : 0

  name        = var.name
  description = "For Elasticache cluster ${var.name}"
  subnet_ids  = var.subnets

  tags = merge(var.tags, {
    Name = local.name
  })
}

resource "aws_elasticache_replication_group" "default" {
  count = var.create_cluster ? 1 : 0

  auth_token                    = var.transit_encryption_enabled ? var.auth_token : null
  replication_group_id          = var.replication_group_id == "" ? var.name : var.replication_group_id
  replication_group_description = var.name
  node_type                     = var.instance_type
  number_cache_clusters         = var.cluster_mode_enabled ? null : var.cluster_size
  port                          = var.port
  parameter_group_name          = join("", aws_elasticache_parameter_group.default.*.name)
  availability_zones            = length(var.availability_zones) == 0 ? null : [for n in range(0, var.cluster_size) : element(var.availability_zones, n)]
  automatic_failover_enabled    = var.automatic_failover_enabled
  multi_az_enabled              = var.multi_az_enabled
  subnet_group_name             = local.cache_subnet_group_name
  security_group_ids            = var.create_security_group ? [join("", aws_security_group.this.*.id)] : var.existing_security_groups
  maintenance_window            = var.maintenance_window
  notification_topic_arn        = var.notification_topic_arn
  engine_version                = var.engine_version
  at_rest_encryption_enabled    = var.at_rest_encryption_enabled
  transit_encryption_enabled    = var.auth_token != null ? coalesce(true, var.transit_encryption_enabled) : var.transit_encryption_enabled
  kms_key_id                    = var.at_rest_encryption_enabled ? var.kms_key_id : null
  snapshot_name                 = var.snapshot_name
  snapshot_arns                 = var.snapshot_arns
  snapshot_window               = var.snapshot_window
  snapshot_retention_limit      = var.snapshot_retention_limit
  apply_immediately             = var.apply_immediately

  tags = var.tags

  dynamic "cluster_mode" {
    for_each = var.cluster_mode_enabled ? ["true"] : []
    content {
      replicas_per_node_group = var.cluster_mode_replicas_per_node_group
      num_node_groups         = var.cluster_mode_num_node_groups
    }
  }
}


resource "aws_elasticache_parameter_group" "default" {
  count  = var.create_cluster ? 1 : 0
  name   = var.name
  family = var.family

  dynamic "parameter" {
    for_each = var.cluster_mode_enabled ? concat([{ name = "cluster-enabled", value = "yes" }], var.parameter) : var.parameter
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }
}


################################################################################
# Security Groups
################################################################################

resource "aws_security_group" "this" {
  count       = var.create_cluster && var.create_security_group == true ? 1 : 0
  name_prefix = "${var.name}-"
  description = var.security_group_description == "" ? "Control traffic to/from Elasticache Cluster ${var.name}" : var.security_group_description
  vpc_id      = var.vpc_id
  tags = merge(var.tags, var.security_group_tags, {
    Name = local.name
  })
}

resource "aws_security_group_rule" "cluster_chatter_egress" {
  count                    = var.create_cluster && var.create_security_group ? 1 : 0
  description              = "Allow inter-cluster communication"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.this[count.index].id
  security_group_id        = aws_security_group.this[count.index].id
  type                     = "egress"
}
resource "aws_security_group_rule" "cluster_chatter_ingress" {
  count                    = var.create_cluster && var.create_security_group ? 1 : 0
  description              = "Allow inter-cluster communication"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.this[count.index].id
  security_group_id        = aws_security_group.this[count.index].id
  type                     = "ingress"
}

resource "aws_security_group_rule" "security_group_ingress" {
  count                    = var.create_cluster && var.create_security_group ? length(var.allowed_security_groups) : 0
  description              = "Allow outbound traffic to approved security groups"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = element(var.allowed_security_groups, count.index)
  security_group_id        = local.cache_security_group_id
  type                     = "ingress"
}

resource "aws_security_group_rule" "cidr_ingress" {
  count             = var.create_cluster && var.create_security_group && length(var.allowed_cidr_blocks) > 0 ? 1 : 0
  description       = "Allow inbound traffic from approved CIDR blocks"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = local.cache_security_group_id
  type              = "ingress"
}

################################################################################
# Datadog Resources
################################################################################
# To Be Added

################################################################################
# Cloudwatch Resources
################################################################################
# To Be Added
