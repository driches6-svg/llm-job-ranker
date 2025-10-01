# Contract Role Ranker — Phase 1

Ingest, de-duplicate, and store JobServe contract roles (via **Apiify**) into **Amazon S3 as Parquet**, ready for **Athena** queries.  
_Phase 2 will add an LLM-based ranker (OpenAI) to score job fit._

---

## Architecture (Phase 1)

- **Lambda: Ingest**
  - Triggered by **EventBridge** (cron/rate).
  - Fetches listings from **Apiify**.
  - Computes a stable `job_id` per listing.
  - Uses **DynamoDB** as a de-dup gate (`PutItem` + `attribute_not_exists(job_id)`).
  - Writes **partitioned Parquet** (Snappy) to S3 (Hive-style partitions).

- **Amazon S3**
  - Durable, encrypted dataset storage (SSE-S3).
  - Partitioned by **`year/month/day/hour`** (ingest time).

- **Amazon DynamoDB**
  - Lightweight de-dup store.
  - **TTL** expires old `job_id` entries automatically (e.g., 120 days).

> Athena/Glue setup can be added in Phase 2 to query the Parquet dataset.

---

## Repository Structure

```
contract-role-ranker/
├─ README.md
├─ .gitignore
├─ .pre-commit-config.yaml
├─ terraform/
│  ├─ main.tf
│  ├─ variables.tf
│  ├─ versions.tf
│  └─ outputs.tf
└─ lambda_src/
   └─ ingest/
      └─ handler.py
```

---

## Getting Started

### Prerequisites
- **Terraform** ≥ 1.6  
- **AWS CLI** configured with credentials  
- **Python 3.12** (for Lambda source)  
- **Docker** (recommended if packaging `pyarrow`/`awswrangler` via container image)

### Deploy

```bash
git clone https://github.com/<your-user>/contract-role-ranker.git
cd contract-role-ranker/terraform

terraform init
terraform plan
terraform apply
```

Creates:
- S3 bucket for the Parquet dataset  
- DynamoDB table for de-dup (with TTL)  
- Ingest Lambda + EventBridge schedule  
- IAM roles/policies

---

## S3 Data Layout

- **Format:** Parquet (Snappy)  
- **Partitions:** `year`, `month`, `day`, `hour` (ingest time)  
- **Path template:**
  ```
  s3://<bucket>/parquet/jobserve/year=YYYY/month=MM/day=DD/hour=HH/part-*.parquet
  ```
- **Example:**
  ```
  s3://contract-role-data/parquet/jobserve/year=2025/month=10/day=01/hour=09/part-20251001T0900.parquet
  ```

---

## De-duplication

- **`job_id` strategy:** SHA256 over a canonical concatenation, e.g.  
  `canonical_url | title | company | posted_date`
- **DynamoDB gate:**  
  `PutItem` with `ConditionExpression attribute_not_exists(job_id)`
  - New ID → include in batch → write to S3  
  - Existing ID → skip
- **TTL:** entries auto-expire after `DEDUP_TTL_DAYS` (default 120) to keep costs low.

---

## Configuration

### Terraform variables (examples)
- `aws_region` — default `eu-west-2`  
- `apiify_url` — **required** (Apiify endpoint for JobServe)  
- `ingest_schedule` — default `rate(30 minutes)`  
- `s3_bucket_name` — optional explicit bucket name  
- `dedup_ttl_days` — default `120`

### Lambda environment (set by Terraform)
- `BUCKET`  
- `APIIFY_URL`  
- `DEDUP_TABLE`  
- `DEDUP_TTL_DAYS`

> Secrets (Apiify/OpenAI keys) are recommended via **AWS Secrets Manager** (OpenAI used in Phase 2).

---

## Developer Notes

- Prefer packaging the ingest Lambda with **awswrangler + pyarrow** (container image or Lambda Layer) to write Parquet directly.
- Keep Parquet row groups reasonably sized (Wrangler defaults are fine); consider a daily compaction job later if needed.

---

## CI/CD & Linting (recommended)

- **pre-commit** locally for Terraform hygiene:
  - `terraform fmt`, `terraform validate`, `tflint`
- **GitHub Actions** on push/PR:
  - `terraform fmt -check -recursive`
  - `terraform validate`
  - `tflint`
  - (optional) `checkov` or `tfsec` for security scanning

**Developer setup snippet:**
```bash
pip install pre-commit
pre-commit install
```

---

## Next Steps (Phase 2)

- Add **Ranker Lambda** (S3 event) to score jobs with OpenAI and write to `s3://…/scored/…`
- Create **Glue tables / Athena views** for both datasets
- Add pre-LLM **filters** (e.g., day-rate detection, IR35 signals) to save tokens
- Optional: **Redshift Serverless** if you need heavier joins/materialized views

---

## License

MIT — feel free to fork and adapt.
