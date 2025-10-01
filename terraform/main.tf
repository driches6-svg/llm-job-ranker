provider "aws" {
  region = var.aws_region
}

locals {
  bucket_name = coalesce(var.s3_bucket_name, "${var.project}-data-${random_id.suffix.hex}")
}

# Uniqueness helper
resource "random_id" "suffix" {
  byte_length = 3
}

# -------------------------
# S3 BUCKET (Parquet dataset)
# -------------------------
resource "aws_s3_bucket" "jobs" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "jobs" {
  bucket = aws_s3_bucket.jobs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "jobs" {
  bucket = aws_s3_bucket.jobs.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}

resource "aws_s3_bucket_public_access_block" "jobs" {
  bucket                  = aws_s3_bucket.jobs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Root prefixes (optional – nice for browsing)
resource "aws_s3_object" "prefix_parquet" {
  bucket = aws_s3_bucket.jobs.id
  key    = "parquet/jobserve/"
  acl    = "private"
}

# -------------------------
# DYNAMODB (dedup gate)
# -------------------------
resource "aws_dynamodb_table" "dedup" {
  name         = "${var.project}_dedup"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute { name = "job_id" type = "S" }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = var.tags
}

# -------------------------
# IAM ROLES & POLICIES
# -------------------------
data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest_role" {
  name               = "${var.project}_ingest_role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.tags
}

# Basic logging
resource "aws_iam_role_policy_attachment" "ingest_logs" {
  role       = aws_iam_role.ingest_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 write access (parquet target)
data "aws_iam_policy_document" "ingest_s3" {
  statement {
    sid       = "PutParquet"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.jobs.arn}/parquet/*"]
  }
}

resource "aws_iam_policy" "ingest_s3" {
  name   = "${var.project}_ingest_s3_policy"
  policy = data.aws_iam_policy_document.ingest_s3.json
}

resource "aws_iam_role_policy_attachment" "ingest_s3_attach" {
  role       = aws_iam_role.ingest_role.name
  policy_arn = aws_iam_policy.ingest_s3.arn
}

# DynamoDB dedup PutItem
data "aws_iam_policy_document" "ingest_ddb" {
  statement {
    sid     = "DDBPut"
    actions = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.dedup.arn]
  }
}

resource "aws_iam_policy" "ingest_ddb" {
  name   = "${var.project}_ingest_ddb_policy"
  policy = data.aws_iam_policy_document.ingest_ddb.json
}

resource "aws_iam_role_policy_attachment" "ingest_ddb_attach" {
  role       = aws_iam_role.ingest_role.name
  policy_arn = aws_iam_policy.ingest_ddb.arn
}

# -------------------------
# ECR (for Lambda image)
# -------------------------
resource "aws_ecr_repository" "ingest" {
  name                 = "${var.project}/ingest"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = var.tags
}

# Optional lifecycle: keep last 10 images
resource "aws_ecr_lifecycle_policy" "ingest" {
  repository = aws_ecr_repository.ingest.name
  policy     = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Keep last 10 images",
      selection    = {
        tagStatus     = "any",
        countType     = "imageCountMoreThan",
        countNumber   = 10
      },
      action       = { type = "expire" }
    }]
  })
}

# -------------------------
# LAMBDA (INGEST, container image)
# -------------------------
resource "aws_lambda_function" "ingest" {
  function_name = "${var.project}_ingest"
  role          = aws_iam_role.ingest_role.arn

  package_type  = "Image"
  image_uri     = var.ingest_image_uri != "" ? var.ingest_image_uri : "${aws_ecr_repository.ingest.repository_url}:placeholder"

  timeout     = 120
  memory_size = 1024
  architectures = ["x86_64"]

  environment {
    variables = {
      BUCKET          = aws_s3_bucket.jobs.bucket
      APIIFY_URL      = var.apiify_url
      DEDUP_TABLE     = aws_dynamodb_table.dedup.name
      DEDUP_TTL_DAYS  = tostring(var.dedup_ttl_days)
      # Any other flags your handler expects, e.g. PARQUET_WRITE="1"
    }
  }

  tags = var.tags
}

# Permission for EventBridge to invoke the Lambda
resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowEventInvokeIngest"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingest_schedule.arn
}

# -------------------------
# EVENTBRIDGE SCHEDULE
# -------------------------
resource "aws_cloudwatch_event_rule" "ingest_schedule" {
  name                = "${var.project}_ingest_schedule"
  schedule_expression = var.ingest_schedule
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "ingest_target" {
  rule      = aws_cloudwatch_event_rule.ingest_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.ingest.arn
}

# -------------------------
# OPTIONAL: CloudWatch log group retention (keep costs tidy)
# -------------------------
resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 14
  tags              = var.tags
}