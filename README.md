# Contract Role Ranker (Phase 1)

Ingest, deduplicate, and store contract job listings from JobServe (via Apiify) into AWS S3.  
This is the first phase of a pipeline that will later enrich listings with LLM scoring and ranking.

---

## 📌 Architecture (Phase 1)

- **AWS Lambda (Ingest)**
  - Triggered on a schedule (EventBridge).
  - Pulls listings from Apiify (JobServe scraper API).
  - Computes a stable `job_id` for each listing.
  - Checks DynamoDB to avoid duplicates.
  - Writes **partitioned Parquet files** to S3.

- **AWS S3**
  - Storage for listings, partitioned by `year/month/day/hour`.
  - Encrypted at rest (AES-256).

- **AWS DynamoDB**
  - Lightweight deduplication store.
  - Each `job_id` stored with TTL (default 120 days) to expire old jobs automatically.

- **Athena (later)**
  - Query-ready dataset thanks to Parquet + Hive-style partitions.

---

## 🚀 Getting Started

### Prerequisites
- Terraform `>= 1.6`
- AWS CLI with credentials configured
- Python 3.12 (for Lambda source code)
- Docker (if packaging Lambdas with container images)

### Setup

Clone this repository:

```bash
git clone https://github.com/<your-user>/contract-role-ranker.git
cd contract-role-ranker/terraform