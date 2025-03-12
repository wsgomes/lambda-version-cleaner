terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.30.0"
    }
  }

  backend "s3" {}
  required_version = ">= 0.14.9"
}

variable "name" {
  type     = string
  default  = "lambda-version-cleaner"
  nullable = false
}

variable "aws_region" {
  type     = string
  default  = "us-east-1"
  nullable = false
}

provider "aws" {
  region = var.aws_region
}

variable "terraform_state" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^(prod|dev-pr[0-9]+)$", var.terraform_state))
    error_message = "The terraform_state variable must be 'prod' or 'dev-pr<PR_NUMBER>' where <PR_NUMBER> is a positive integer."
  }
}

variable "schedule_expression" {
  type     = string
  default  = "cron(0 3 * * ? *)"
  nullable = false
}

variable "versions_to_keep" {
  type     = string
  default  = "3"
  nullable = false
}

data "aws_caller_identity" "current" {}

locals {
  tags = {
    ManagedBy = "https://github.com/wsgomes/lambda-version-cleaner"
  }
}

#***********************************************************************************************************************
# Roles and Policies
#***********************************************************************************************************************

resource "aws_iam_role" "lambda_role" {
  name                  = "${var.name}_role"
  tags                  = local.tags
  force_detach_policies = true

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com",
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.name}_policy"
  description = "IAM policy for Lambda execution"
  tags        = local.tags

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect   = "Allow",
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*",
      },
      {
        Action = [
          "lambda:ListFunctions",
        ]
        Effect   = "Allow",
        Resource = "*",
      },
      {
        Action = [
          "lambda:ListVersionsByFunction",
          "lambda:DeleteFunction",
        ]
        Effect   = "Allow",
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:*",
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

#***********************************************************************************************************************
# Lambda Function
#***********************************************************************************************************************

resource "aws_s3_bucket" "storage" {
  bucket        = var.name
  tags          = local.tags
  force_destroy = true
}

resource "null_resource" "lambda_trigger" {
  triggers = {
    handler = filemd5("./handler.py") # Watch the file for changes
  }
}

data "archive_file" "lambda_exporter" {
  type             = "zip"
  source_file      = "./handler.py"
  output_path      = "./handler.zip"
  output_file_mode = "0666"
}

resource "aws_s3_object" "lambda_handler_zip" {
  bucket        = aws_s3_bucket.storage.id
  key           = "lambda/handler.zip"
  source        = data.archive_file.lambda_exporter.output_path
  etag          = filemd5(data.archive_file.lambda_exporter.output_path) # Ensures the file is uploaded only if it has changed
  tags          = local.tags
  acl           = "private"
  force_destroy = true
}

resource "aws_lambda_function" "lambda_function" {
  function_name = "${var.name}_lambda"
  role          = aws_iam_role.lambda_role.arn
  tags          = local.tags
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  publish       = true
  memory_size   = 128
  timeout       = 900 # 15 minutes

  s3_bucket        = aws_s3_bucket.storage.id
  s3_key           = aws_s3_object.lambda_handler_zip.key
  source_code_hash = filebase64sha256(data.archive_file.lambda_exporter.output_path) # Ensures the file is uploaded only if it has changed

  environment {
    variables = {
      THIS_AWS_REGION       = var.aws_region       # Pass the region to the Lambda function (use defualt region if not set)
      VERSIONS_TO_KEEP      = var.versions_to_keep # Amount of most recent versions to keep
      FUNCTION_NAME_PATTERN = ".*"                 # Match all functions
      FUNCTION_NAMES        = ""                   # Empty string to match all functions
    }
  }
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "current"
  function_name    = aws_lambda_function.lambda_function.function_name
  function_version = aws_lambda_function.lambda_function.version
}

#***********************************************************************************************************************
# CloudWatch Events
#***********************************************************************************************************************

resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "${var.name}_rule"
  schedule_expression = var.schedule_expression
  is_enabled          = false
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  target_id = "${var.name}_target"
  rule      = aws_cloudwatch_event_rule.lambda_schedule.name
  arn       = aws_lambda_function.lambda_function.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule.arn
}

#***********************************************************************************************************************
# Outputs
#***********************************************************************************************************************

output "s3_bucket_name" {
  value = aws_s3_bucket.storage.bucket
}
