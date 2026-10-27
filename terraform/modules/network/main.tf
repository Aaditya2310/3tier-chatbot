# VPC across 2 AZs with three subnet tiers:
#   public : ALB + NAT          — route to Internet Gateway
#   app    : EC2 app + monitor  — route to NAT (outbound only)
#   db     : RDS                — NO route to the internet at all
data "aws_availability_zones" "available" { state = "available" }

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  # /16 split into /24s: public 0-1, app 10-11, db 20-21. Gaps leave room to grow.
  public_cidrs = [for i in range(2) : cidrsubnet(var.cidr, 8, i)]
  app_cidrs    = [for i in range(2) : cidrsubnet(var.cidr, 8, i + 10)]
  db_cidrs     = [for i in range(2) : cidrsubnet(var.cidr, 8, i + 20)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # needed for RDS endpoint resolution and SSM
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # only the NAT instance gets a public IP, explicitly
  tags                    = { Name = "${var.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name}-app-${local.azs[count.index]}", Tier = "app" }
}

resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.db_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name}-db-${local.azs[count.index]}", Tier = "db" }
}

# ---------- route tables ----------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-app" }
}

resource "aws_route" "app_nat_gateway" {
  count                  = var.nat_mode == "gateway" ? 1 : 0
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route" "app_nat_instance" {
  count                  = var.nat_mode == "instance" ? 1 : 0
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# DB route table: only the implicit "local" route. This is what makes the tier isolated.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-db" }
}

resource "aws_route_table_association" "db" {
  count          = 2
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# Free gateway endpoint: S3 traffic (e.g. dnf repos on AL2023, SSM agent updates) skips the NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id]
  tags              = { Name = "${var.name}-s3" }
}

# ---------- NAT option A: managed NAT Gateway (single AZ — not HA, documented tradeoff) ----------
resource "aws_eip" "nat" {
  count  = var.nat_mode == "gateway" ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.name}-nat" }
}

resource "aws_nat_gateway" "this" {
  count         = var.nat_mode == "gateway" ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.name}-nat" }
  depends_on    = [aws_internet_gateway.this]
}

# ---------- NAT option B: NAT instance (much cheaper, you own patching and availability) ----------
data "aws_ssm_parameter" "al2023_arm" {
  count = var.nat_mode == "instance" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "nat" {
  count       = var.nat_mode == "instance" ? 1 : 0
  name        = "${var.name}-nat"
  description = "NAT instance: accept traffic from inside the VPC only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc" {
  count             = var.nat_mode == "instance" ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  cidr_ipv4         = var.cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "nat_out" {
  count             = var.nat_mode == "instance" ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "nat" {
  count                       = var.nat_mode == "instance" ? 1 : 0
  ami                         = data.aws_ssm_parameter.al2023_arm[0].value
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  associate_public_ip_address = true
  source_dest_check           = false # required: it forwards packets that aren't addressed to it
  metadata_options { http_tokens = "required" }
  user_data = <<-SH
    #!/bin/bash
    set -euxo pipefail
    dnf install -y iptables-services
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/90-nat.conf
    sysctl --system
    IFACE=$(ip route | awk '/^default/ {print $5; exit}')
    iptables -t nat -A POSTROUTING -o "$IFACE" -s ${var.cidr} -j MASQUERADE
    iptables -F FORWARD
    service iptables save
    systemctl enable --now iptables
  SH
  tags      = { Name = "${var.name}-nat" }
  # New AL2023 AMIs would otherwise force-replace this instance on every plan.
  lifecycle { ignore_changes = [ami] }
}
