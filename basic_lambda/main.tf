variable "vpc_cidr_block" {}
variable "public_subnet_cidr_blocks" {}
variable "private_subnet_cidr_blocks" {}
variable "avail_zones" {}
variable "aws_region" {}
variable "bucketName" {}
variable "npm_token" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  cidr   = var.vpc_cidr_block

  azs             = var.avail_zones
  private_subnets = var.private_subnet_cidr_blocks
  public_subnets  = var.public_subnet_cidr_blocks

  enable_nat_gateway     = true
  enable_vpn_gateway     = false
  one_nat_gateway_per_az = true

  tags = {
    Terraform = "true"
    Name      = "testerloop-vpc"
  }
}

// Create the ecr repository
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

// Create the inbound and outbound security group rules
resource "aws_security_group_rule" "testerloop-security-group-rule-inbound-sg" {
  depends_on               = [module.vpc]
  type                     = "ingress"
  security_group_id        = module.vpc.default_security_group_id
  description              = "Allow all inbound traffic from the security group"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.vpc.default_security_group_id
}

resource "aws_security_group_rule" "testerloop-security-group-rule-inbound-ipv4" {
  depends_on        = [aws_security_group_rule.testerloop-security-group-rule-inbound-sg]
  type              = "ingress"
  security_group_id = module.vpc.default_security_group_id
  description       = "Allow all inbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "testerloop-security-group-rule-outbound-sg" {
  depends_on               = [aws_security_group_rule.testerloop-security-group-rule-inbound-ipv4]
  type                     = "egress"
  security_group_id        = module.vpc.default_security_group_id
  description              = "Allow all outbound traffic from the security group"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.vpc.default_security_group_id
}

resource "aws_security_group_rule" "testerloop-security-group-rule-outbound-ipv4" {
  depends_on        = [aws_security_group_rule.testerloop-security-group-rule-outbound-sg]
  type              = "egress"
  security_group_id = module.vpc.default_security_group_id
  description       = "Allow all outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}


// Create the s3 bucket
resource "aws_s3_bucket" "testerloopS3Bucket" {
  bucket = var.bucketName
}



// Create the service role for the lambda
resource "aws_iam_role" "testerloopLambdaCypressRole" {
  path                 = "/service-role/"
  name                 = "testerloop-cypress-lambda-role"
  assume_role_policy   = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
  max_session_duration = 3600
  tags                 = {}
}

// Create the policy to write to s3
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

// Create the policy to allow the lambda to attach to the VPC
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

// Create the lalmbda function
resource "aws_lambda_function" "testerloopLambdaFunction" {
  #   depends_on  = [null_resource.docker_build_and_push]
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
    subnet_ids = [module.vpc.private_subnets[0]]
    security_group_ids = [
      module.vpc.default_security_group_id
    ]
  }
}


