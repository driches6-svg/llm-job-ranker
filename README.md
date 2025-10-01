title: "Contract Role Ranker (Phase 1)"
tagline: "Ingest, deduplicate, and store JobServe contract roles in S3 as Parquet; query-ready for Athena."
status: "phase-1-ingest"

architecture:
  - component: "AWS Lambda (Ingest)"
    details:
      - "Triggered on a schedule (EventBridge)."
      - "Calls Apiify (JobServe scraper API)."
      - "Computes stable job_id and filters duplicates via DynamoDB."
      - "Writes partitioned Parquet to S3 (Hive-style)."
  - component: "AWS S3"
    details:
      - "Primary storage for listings."
      - "Encrypted at rest (SSE-S3 / AES-256)."
      - "Partitioned by year/month/day/hour for efficient queries."
  - component: "AWS DynamoDB"
    details:
      - "Lightweight dedupe gate: PutItem with ConditionExpression."
      - "TTL auto-expires old entries (default 120 days)."
  - component: "Amazon Athena (later)"
    details:
      - "Query dataset directly from S3 (Parquet)."
      - "Add Glue Crawler or manual DDL in Phase 2."

repo_structure: |
  contract-role-ranker/
  ├─ README.md
  ├─ .pre-commit-config.yaml
  ├─ .gitignore
  ├─ terraform/
  │  ├─ main.tf
  │  ├─ variables.tf
  │  ├─ versions.tf
  │  └─ outputs.tf
  ├─ lambda_src/
  │  ├─ ingest/handler.py
  │  └─ (phase-2) ranker/handler.py
  └─ .github/workflows/
     └─ terraform-lint.yml

getting_started:
  prerequisites:
    - "Terraform >= 1.6"
    - "AWS CLI with credentials configured"
    - "Python 3.12 (Lambda source)"
    - "Docker (if packaging with container images for pyarrow/awswrangler)"
  setup:
    steps:
      - name: "Clone repo"
        run: |
          git clone https://github.com/<your-user>/contract-role-ranker.git
          cd contract-role-ranker/terraform
      - name: "Initialize Terraform"
        run: |
          terraform init
      - name: "Plan & Apply"
        run: |
          terraform plan
          terraform apply
    creates:
      - "S3 bucket for Parquet dataset"
      - "DynamoDB table for dedupe with TTL"
      - "Lambda ingest function + EventBridge schedule"
      - "IAM roles/policies for least-privilege access"

s3_data_layout:
  format: "Parquet (Snappy)"
  partitioning: "year/month/day/hour (ingest time)"
  path_template: "s3://<bucket>/parquet/jobserve/year=YYYY/month=MM/day=DD/hour=HH/part-*.parquet"
  example_path: "s3://contract-role-data/parquet/jobserve/year=2025/month=10/day=01/hour=09/part-20251001T0900.parquet"

deduplication:
  job_id_strategy: "SHA256 over canonical_url | title | company | posted_date"
  dynamodb:
    table: "jobserve_dedup"
    operation: "PutItem with ConditionExpression attribute_not_exists(job_id)"
    result:
      - "New ID → write to S3"
      - "Existing ID → skip"
    ttl_days_default: 120
    notes:
      - "Keeps table small and cheap"
      - "Prevents duplicates across runs/days"

configuration:
  terraform_variables:
    - name: "aws_region"
      default: "eu-west-2"
      description: "Deployment region"
    - name: "apiify_url"
      required: true
      description: "Apiify endpoint for JobServe feed"
    - name: "ingest_schedule"
      default: "rate(30 minutes)"
      description: "EventBridge schedule expression"
    - name: "s3_bucket_name"
      default: null
      description: "Optional explicit bucket name"
    - name: "dedup_ttl_days"
      default: 120
      description: "DynamoDB TTL for job_id records"
  lambda_env:
    - "BUCKET"
    - "APIIFY_URL"
    - "DEDUP_TABLE"
    - "DEDUP_TTL_DAYS"
  secrets:
    recommended: "Store Apiify/OpenAI keys in AWS Secrets Manager (Phase 2 for OpenAI)."

development_notes:
  formatting_and_lint:
    - "Use pre-commit for terraform fmt/validate and tflint."
    - "CI runs terraform fmt -check, validate, tflint."
  python_lambda:
    - "Format with black; lint with flake8."
    - "For Parquet writes, package awswrangler + pyarrow via Lambda container image or Lambda layer."
  athena_integration:
    - "Add Glue Crawler or CREATE EXTERNAL TABLE in Phase 2."
    - "Run MSCK REPAIR TABLE after new partitions land (if manual DDL)."

next_steps_phase_2:
  - "Add Ranker Lambda (S3 event) to score jobs with OpenAI and write to s3://.../scored/…"
  - "Create Glue tables / Athena views for raw vs scored datasets."
  - "Add filters (e.g., day-rate detection, IR35 signals) before LLM to reduce tokens."
  - "Optional: Redshift Serverless if you need complex joins/materialized views."

license:
  type: "MIT"
  note: "Feel free to fork and adapt."

acknowledgements:
  - "Apiify for scraping interface to JobServe."
  - "awswrangler for convenient Parquet dataset writes."