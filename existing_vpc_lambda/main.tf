variable "public_subnet_cidr_blocks" {}
variable "private_subnet_cidr_blocks" {}
variable "avail_zones" {}
variable "aws_region" {}
variable "npm_token" {}
variable "vpc_id" {}
variable "bucketName" {}
variable "elastic_ip_address" {
  type    = string
  default = null
}


# // Create the ecr repository
resource "aws_ecr_repository" "testerloop-lambda-ecr-repository" {
  name = "testerloop-lambda-ecr-repository"
}

// Build and push the docker image to be used by the lambda
resource "null_resource" "docker_build_and_push" {
  depends_on = [aws_ecr_repository.testerloop-lambda-ecr-repository]
  provisioner "local-exec" {
    command = <<EOT
                 aws ecr get-login-password --region ${var.aws_region} | 
                 docker login --username AWS --password-stdin ${aws_ecr_repository.testerloop-lambda-ecr-repository.repository_url} && 
                 docker build --build-arg NPM_TOKEN=${var.npm_token} -t ${aws_ecr_repository.testerloop-lambda-ecr-repository.repository_url}:latest -f Dockerfile . &&
                 docker push ${aws_ecr_repository.testerloop-lambda-ecr-repository.repository_url}:latest 
                 EOT
  }
}


// Check for existing internet gateway
data "aws_internet_gateway" "existing" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

locals {
  internet_gateway_exists = length(data.aws_internet_gateway.existing.id) > 0
}

// Create a new ig or skip if there is already an existing
variable "skip_instance_creation" { default = true }

# Internet Gateway for Public Subnet
resource "aws_internet_gateway" "testerloop-igw" {
  # Conditional dependency on the existence of an internet gateway
  count = var.skip_instance_creation && !local.internet_gateway_exists ? 1 : 0

  depends_on = [data.aws_internet_gateway.existing]
  vpc_id     = var.vpc_id
  tags = {
    Name      = "testerloop-igw"
    Terraform = true
  }
}

// Elastic-IP (eip) for NAT. Make sure a slot is available
resource "aws_eip" "testerloop-nat-eip" {
  count  = var.elastic_ip_address != null ? 0 : 1
  domain = "vpc"
  tags = {
    Name      = "testerloop-nat-eip"
    Terraform = true
  }
}

locals {
  assinged_eip = var.elastic_ip_address != null ? var.elastic_ip_address : aws_eip.testerloop-nat-eip[0].id
}



# NAT
resource "aws_nat_gateway" "testerloop-nat" {
  allocation_id = local.assinged_eip
  subnet_id     = element(aws_subnet.testerloop-public-subnet.*.id, 0)

  tags = {
    Name      = "testerloop-nat"
    Terraform = true
  }
}

# Public subnet
resource "aws_subnet" "testerloop-public-subnet" {
  vpc_id                  = var.vpc_id
  count                   = length(var.public_subnet_cidr_blocks)
  cidr_block              = element(var.public_subnet_cidr_blocks, count.index)
  availability_zone       = element(var.avail_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name      = "testerloop ${element(var.avail_zones, count.index)}-public-subnet"
    Terraform = true
  }
}

# Private Subnet
resource "aws_subnet" "testerloop-private-subnet" {
  vpc_id                  = var.vpc_id
  count                   = length(var.private_subnet_cidr_blocks)
  cidr_block              = element(var.private_subnet_cidr_blocks, count.index)
  availability_zone       = element(var.avail_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name      = "testerloop-${element(var.avail_zones, count.index)}-private-subnet"
    Terraform = true
  }
}

# Routing tables to route traffic for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = {
    Name      = "testerloop-private-route-table"
    Terraform = true
  }
}

# Routing tables to route traffic for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  tags = {
    Name      = "testerloop-public-route-table"
    Terraform = true
  }
}

# Route for Internet Gateway
resource "aws_route" "public_internet_gateway" {
  # Conditional dependency on the existence of an internet gateway
  # count      = !local.internet_gateway_exists ? 1 : 0
  depends_on = [data.aws_internet_gateway.existing]

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.existing.id
}

# Route for NAT
resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.testerloop-nat.id
}


# Route table associations for both Public & Private Subnets
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidr_blocks)
  subnet_id      = element(aws_subnet.testerloop-public-subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidr_blocks)
  subnet_id      = element(aws_subnet.testerloop-private-subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}


data "aws_security_group" "existing_sg" {
  vpc_id = var.vpc_id
}

# Default Security Group of VPC
resource "aws_security_group" "testerloop-sg" {
  // Skip creating a new security group if already exists
  count       = length(data.aws_security_group.existing_sg.id) > 0 ? 0 : 1
  name        = "testerloop-default-sg"
  description = "Default Testerloop SG to alllow traffic from the VPC"
  vpc_id      = var.vpc_id

  tags = {
    Terraform = true
  }
}

// If a security group already exists use that one, else use the created one
locals {
  selected_sg = length(data.aws_security_group.existing_sg.id) > 0 ? data.aws_security_group.existing_sg : aws_security_group.testerloop-sg[0]
}

// Create the inbound and outbound security group rules
resource "aws_security_group_rule" "testerloop-security-group-rule-inbound-sg" {
  count                    = length(data.aws_security_group.existing_sg.id) > 0 ? 0 : 1
  type                     = "ingress"
  security_group_id        = local.selected_sg.id
  description              = "Allow all inbound traffic from the security group"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = local.selected_sg.id
}

resource "aws_security_group_rule" "testerloop-security-group-rule-inbound-ipv4" {
  count             = length(data.aws_security_group.existing_sg.id) > 0 ? 0 : 1
  type              = "ingress"
  security_group_id = local.selected_sg.id
  description       = "Allow all inbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "testerloop-security-group-rule-outbound-sg" {
  count                    = length(data.aws_security_group.existing_sg.id) > 0 ? 0 : 1
  type                     = "egress"
  security_group_id        = local.selected_sg.id
  description              = "Allow all outbound traffic from the security group"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = local.selected_sg.id
}

resource "aws_security_group_rule" "testerloop-security-group-rule-outbound-ipv4" {
  count             = length(data.aws_security_group.existing_sg.id) > 0 ? 0 : 1
  type              = "egress"
  security_group_id = local.selected_sg.id
  description       = "Allow all outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}


# // Create the s3 bucket
resource "aws_s3_bucket" "testerloopS3Bucket" {
  bucket = var.bucketName
}



# // Create the service role for the lambda
resource "aws_iam_role" "testerloopLambdaCypressRole" {
  path                 = "/service-role/"
  name                 = "testerloop-cypress-lambda-role"
  assume_role_policy   = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
  max_session_duration = 3600
  tags                 = {}
}

# // Create the policy to write to s3
resource "aws_iam_role_policy" "testerloopWriteResultsToS3Policy" {
  name   = "TesterloopS3WriteResultsPolicy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:AbortMultipartUpload",
                "s3:ListBucket",
                "s3:GetObjectVersion",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "${aws_s3_bucket.testerloopS3Bucket.arn}/*",
                "${aws_s3_bucket.testerloopS3Bucket.arn}"
            ]
        }
    ]
}
EOF
  role   = aws_iam_role.testerloopLambdaCypressRole.name
}

# // Create the policy to allow the lambda to attach to the VPC
resource "aws_iam_role_policy" "testerloopEnableLambdaToAttachVpcPolicy" {
  name   = "LambdaVPCAccessExecutionPolicy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "ec2:AttachNetworkInterface",
                "ec2:DescribeDhcpOptions",
                "ec2:DescribeInstances",
                "ec2:DescribeRouteTables",
                "ec2:CreateNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DeleteNetworkInterface",
                "ec2:AssignPrivateIpAddresses",
                "ec2:UnassignPrivateIpAddresses"
            ],
            "Resource": "*"

        }
    ]
}
EOF
  role   = aws_iam_role.testerloopLambdaCypressRole.name
}

# // Create the lalmbda function
resource "aws_lambda_function" "testerloopLambdaFunction" {
  depends_on  = [data.aws_security_group.existing_sg, aws_subnet.testerloop-public-subnet, aws_subnet.testerloop-private-subnet]
  description = "Lambda function for executing the Testerloop tests"

  function_name = "testerloop-cypress-lambda"
  architectures = [
    "x86_64"
  ]
  package_type = "Image"
  image_uri    = "${aws_ecr_repository.testerloop-lambda-ecr-repository.repository_url}:latest"
  memory_size  = 3008
  role         = aws_iam_role.testerloopLambdaCypressRole.arn
  timeout      = 600

  tracing_config {
    mode = "PassThrough"
  }
  vpc_config {
    subnet_ids = [aws_subnet.testerloop-private-subnet[0].id, aws_subnet.testerloop-public-subnet[0].id]
    security_group_ids = [
      local.selected_sg.id
    ]
  }
}


