output "bucket_name" {
  value       = aws_s3_bucket.jobs.bucket
  description = "S3 bucket used for Parquet dataset"
}

output "dedup_table" {
  value       = aws_dynamodb_table.dedup.name
  description = "DynamoDB table for deduplication"
}

output "ingest_lambda_arn" {
  value       = aws_lambda_function.ingest.arn
  description = "ARN of the ingest Lambda"
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.ingest.repository_url
  description = "ECR repository URL for the ingest Lambda image"
}

output "eventbridge_rule" {
  value       = aws_cloudwatch_event_rule.ingest_schedule.arn
  description = "EventBridge rule ARN that triggers ingest"
}