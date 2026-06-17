# KMS
resource "aws_kms_key" "main" {
  description  = "${local.name} encryption key (RDS + EKS secrets)"
  deletion_window_in_days = 7
  enable_key_rotation = true
  tags = { Name = "${local.name}-kms" }
}

resource "aws_kms_alias" "main" {
  name  = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

# Secrets Manager with IRSA
resource "random_password" "db" {
  length = 24
  special = true
  override_special = "!#$%&*()-_=+[]{}"
}

resource "aws_secretsmanager_secret" "db" {
  name_prefix = "${local.name}-db-credentials-"
  kms_key_id = aws_kms_key.main.arn
  tags = { Name = "${local.name}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname = var.db_name
    host = aws_db_instance.main.address
    port = 5432
  })
}

# RDS Security Group: only from EKS Cluster SG
resource "aws_security_group" "db" {
  name_prefix = "${local.name}-db-"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from EKS cluster SG"
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  tags = { Name = "${local.name}-db-sg" }
  lifecycle { create_before_destroy = true }
}

# RDS PostgreSQL: MultiAZ + KMS
resource "aws_db_subnet_group" "main" {
  name = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.data[*].id
  tags = { Name = "${local.name}-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier = "${local.name}-db"
  engine = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  max_allocated_storage = 100
  storage_type = "gp3"
  storage_encrypted = true
  kms_key_id = aws_kms_key.main.arn

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  multi_az  = true
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 7
  deletion_protection = false
  skip_final_snapshot = true

  tags = { Name = "${local.name}-rds" }
}
