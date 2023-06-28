variable "vpc_cidr_block" {}
variable "public_subnet_cidr_blocks" {}
variable "private_subnet_cidr_blocks" {}
variable "avail_zones" {}
variable "aws_region" {}
variable "npm_token" {}

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
