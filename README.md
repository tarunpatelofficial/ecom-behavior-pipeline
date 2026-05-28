# ecom-behavior-pipeline

An end-to-end data engineering project that simulates, ingests, transforms, and visualizes e-commerce customer behavior data on AWS.

---

## Architecture

```
Python Simulator
      │
      ▼
Amazon SQS (ecom-behavior-events)
      │
      ▼
AWS Lambda (ecom-events-to-s3)
      │
      ▼
Amazon S3 (raw/events/yyyy/mm/dd/hh/)
      │
      ▼
Amazon Athena (ecom_behavior_db)
      │
      ▼
dbt (staging → intermediate → marts)
      │
      ▼
Apache Superset Dashboard
```

---

## Project Structure

```
ecom-behavior-pipeline/
├── event_simulator.py        # Generates and sends fake e-commerce events to SQS
├── constants.py              # Products, event types, journeys, and lookup lists
├── ecom_behavior/            # dbt project
│   ├── models/
│   │   ├── staging/
│   │   │   ├── sources.yml
│   │   │   ├── schema.yml
│   │   │   └── stg_events.sql
│   │   ├── intermediate/
│   │   │   └── int_purchase_items.sql
│   │   └── marts/
│   │       ├── schema.yml
│   │       ├── fct_sessions.sql
│   │       ├── fct_funnel.sql
│   │       ├── fct_product_performance.sql
│   │       ├── fct_search_analysis.sql
│   │       ├── dim_customers.sql
│   │       └── fct_customer_segments.sql
│   └── dbt_project.yml
```

---

## Components

### 1. Event Simulator (`event_simulator.py`)

Generates realistic e-commerce user sessions and pushes them to AWS SQS.

**Key features:**
- 15 user journey patterns (e.g. browse → search → purchase, cart abandonment)
- Session-aware state: `user_id` and `session_id` consistent across all events in a journey
- Search queries linked to the product opened next in the journey
- Cart state tracked throughout the session (add, remove, purchase)
- Realistic timestamps with random increments between events
- Discount and payment method tracking across session

**Events supported:**
`login`, `logout`, `search`, `open_product`, `add_to_cart`, `remove_from_cart`, `like_product`, `unlike_product`, `apply_filters`, `apply_coupon`, `choose_payment_method`, `abandon_checkout`, `purchase`

**Usage:**
```python
simulate_sessions(100)  # generates and sends 100 sessions to SQS
```

---

### 2. AWS Infrastructure

| Service | Resource | Purpose |
|---|---|---|
| SQS | `ecom-behavior-events` | Event message queue |
| Lambda | `ecom-events-to-s3` | Reads SQS, writes to S3 as newline-delimited JSON |
| S3 | `ecommerce-events-raw-tarun` | Raw event storage, partitioned by `year/month/day/hour` |
| Athena | `ecom_behavior_db` | Serverless SQL on S3 data |

**S3 folder structure:**
```
raw/
└── events/
    └── 2026/
        └── 05/
            └── 20/
                └── 15/
                    └── 20260520153045123456.json
```

**Lambda behavior:** Batches up to 10 SQS messages per invocation and writes them as newline-delimited JSON (one event per line) to S3.

---

### 3. dbt Models

#### Staging
| Model | Description |
|---|---|
| `stg_events` | Cleans raw events — casts timestamp, filters null base fields |

#### Intermediate
| Model | Description |
|---|---|
| `int_purchase_items` | Unnests `cart_items` JSON array into one row per product per purchase |

#### Marts
| Model | Description |
|---|---|
| `fct_sessions` | One row per session — duration, event count, purchase flag |
| `fct_funnel` | Purchase funnel counts across all sessions |
| `fct_product_performance` | Views, add-to-carts, purchases, and revenue per product |
| `fct_search_analysis` | Search query counts, avg results, conversion to purchase |
| `dim_customers` | One row per user — lifetime spend, sessions, favorite category |
| `fct_customer_segments` | Classifies each user into a behavior segment |

#### Customer Segments
| Segment | Rule |
|---|---|
| High Value Buyer | `total_spent > 2000` |
| Coupon Hunter | `ever_used_coupon = 1` AND `total_purchases > 0` |
| Cart Abandoner | `ever_abandoned_checkout = 1` AND `total_purchases = 0` |
| Window Shopper | `total_purchases = 0` AND `ever_abandoned_checkout = 0` |
| Comparison Shopper | `total_searches >= 2` AND `total_purchases > 0` |
| Quick Buyer | `total_purchases > 0` AND `total_searches <= 1` |

---

### 4. Data Quality Tests

49 dbt tests across all models covering:
- `not_null` on all critical columns
- `unique` on primary keys (`session_id`, `user_id`, `product_id`)
- `accepted_values` on `event_type`, `payment_type`, `customer_segment`, `category`

Run tests:
```bash
dbt test
```

---

### 5. Superset Dashboard

Charts:
- **Funnel Scorecards** — 6 big number cards showing each funnel stage
- **Customer Segments** — pie chart of segment distribution
- **Top 10 Products by Revenue** — bar chart
- **Top Search Queries** — bar chart of most searched terms
- **Top Customers** — table of highest spenders with favorite category

---

## Setup

### Prerequisites
- Python 3.9+
- AWS account with free tier
- Docker (for Superset)

### AWS Setup
1. Create IAM user with `AmazonSQSFullAccess`, `AmazonS3FullAccess`, `AWSGlueConsoleFullAccess`, `AmazonAthenaFullAccess`
2. Create SQS queue: `ecom-behavior-events`
3. Create S3 bucket: `ecommerce-events-raw-tarun`
4. Create Lambda function `ecom-events-to-s3` with SQS trigger (batch size 10)
5. Create Athena database `ecom_behavior_db` and define events table pointing to S3

### Python Setup
```bash
python -m venv .venv
.venv\Scripts\activate
pip install faker boto3
```

Configure AWS credentials:
```bash
aws configure
```

### Generate Data
```bash
python event_simulator.py  # edit simulate_sessions(n) for desired volume
```

### dbt Setup
```bash
pip install dbt-athena-community
cd ecom_behavior
dbt debug       # verify connection
dbt run         # build all models
dbt test        # run all tests
```

### Superset Setup
```bash
docker run -d -p 8088:8088 -e "SUPERSET_SECRET_KEY=supersecretkey123" --name superset apache/superset
docker exec -it superset superset fab create-admin --username admin --firstname Admin --lastname User --email admin@example.com --password admin123
docker exec -it superset superset db upgrade
docker exec -it superset superset init
docker exec -u root -it superset /app/.venv/bin/python -m ensurepip
docker exec -u root -it superset /app/.venv/bin/python -m pip install "PyAthena[SQLAlchemy]"
docker restart superset
```

Connect to Athena using:
```
awsathena+rest://ACCESSKEY:SECRETKEY@athena.eu-north-1.amazonaws.com:443/ecom_behavior_db?s3_staging_dir=s3%3A%2F%2Fecommerce-events-raw-tarun%2Fathena-results%2F&region_name=eu-north-1
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Python 3.12 |
| Message Queue | AWS SQS |
| Serverless Compute | AWS Lambda |
| Storage | AWS S3 |
| Query Engine | AWS Athena |
| Transformation | dbt (dbt-athena-community) |
| Visualization | Apache Superset |
| Infrastructure | AWS Free Tier |


## Dashboard Preview

![Ecom Behavior Dashboard](assets/dashboard.jpg)