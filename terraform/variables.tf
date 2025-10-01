variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}

variable "project" {
  description = "Name prefix for resources"
  type        = string
  default     = "contract-role-ranker"
}

variable "s3_bucket_name" {
  description = "Optional custom S3 bucket name; if null, a unique one will be generated"
  type        = string
  default     = null
}

variable "apiify_url" {
  description = "Apiify endpoint for the JobServe feed"
  type        = string
}

variable "ingest_schedule" {
  description = "EventBridge schedule expression for the ingest Lambda"
  type        = string
  default     = "rate(30 minutes)"
}

variable "dedup_ttl_days" {
  description = "TTL (days) for dedupe entries in DynamoDB"
  type        = number
  default     = 120
}

variable "ingest_image_uri" {
  description = "Full ECR image URI (including tag) to deploy for the ingest Lambda. If empty, Lambda will wait until you push and update."
  type        = string
  default     = "" # e.g., "<acct>.dkr.ecr.eu-west-2.amazonaws.com/contract-role-ranker/ingest:latest"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {
    app         = "contract-role-ranker"
    environment = "dev"
    owner       = "dave"
  }
}