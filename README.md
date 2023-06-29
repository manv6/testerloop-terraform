# Testerloop Terraform Scripts

Disclaimer: This guide assumes that the user has knowledge of `AWS web services` and `Terraform`

## Description

What's included:

- basic_lambda: Creates a VPC and all the relevant resources from scratch
- existing_vpc_lambda: Attaches to an already existing VPC
- lambda_Dockerfile: Template to place in your test codebase
- lambda handler.js: Template to place in your test codebase inside a 'lambda' directory as index.js

# How to use

- Select the relevant option for your case
- Update the `terraform.tfvars` file with the relevant options
- Execute the terraform commands in the specified directory

# Option 1: Basic Lambda

NOTE: This option will also create a docker image to push to the registry.

Requirements:

- AWS Credentials
- Terraform
- Docker

1. Place the terraform files in your test directory
2. Add the relevant Dockerfile in the test directory
3. Add the relevant lambda index handler in the test directory
4. Change the desired variables in `terraform.tfvars`
   - npm_token will be provided to you by Testerloop team
5. Run the terraform commands:

- terraform init
- terraform apply

# Option 2: Existing VPC

Note: This option assumes that there is already an existing VPC, a security group, an internet gateway and an available Elastic Ip address. `If no security group is found one will be created`.
Similarly you can specify an elastic Ip address by providing the id in the main.tf file
Requirements:

- AWS Credentials
- Terraform
- Docker
- in AWS: An available Elastic IP address slot
- in AWS: An existing VPC

1. Place the terraform files in your test directory
2. Add the relevant Dockerfile in the test directory
3. Add the relevant lambda index handler in the test directory
4. Change the desired variables in `terraform.tfvars`
   - npm_token will be provided to you by Testerloop team
5. Run the terraform commands:

- terraform init
- terraform apply

IMPORTANT NOTE: Depending on what you already have in your infrastructure you might need to readjust the scripts and re apply
