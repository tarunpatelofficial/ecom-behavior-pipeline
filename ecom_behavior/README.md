# ecom_behavior — dbt Project

This is the transformation layer of the ecom-behavior-pipeline project. It takes raw e-commerce event data from Amazon Athena and builds clean, analytics-ready models using dbt.

---

## Why dbt?

Raw event data in S3 is messy — every event type has different fields, timestamps are strings, purchase items are nested JSON arrays, and there's no business logic applied. dbt solves this by letting us write SQL transformations in layers, test data quality automatically, and document everything in one place.

---

## Data Flow

```
S3 Raw Events (JSON)
      │
      ▼
Athena (ecom_behavior_db.events)
      │
      ▼
stg_events          ← clean & cast raw data
      │
      ├──► int_purchase_items    ← unnest cart items JSON
      │
      ├──► fct_sessions          ← session metrics
      ├──► fct_funnel            ← purchase funnel
      ├──► fct_product_performance
      ├──► fct_search_analysis
      ├──► dim_customers
      └──► fct_customer_segments
```

---

## Model Layers

### Staging (`models/staging/`)

One model that sits directly on top of the raw Athena table.

#### `stg_events`
**Why:** Raw events have string timestamps, potential nulls in critical fields, and no type casting. This model cleans all of that up before anything else touches the data.

**What it does:**
- Casts `timestamp` from string to proper TIMESTAMP using `date_parse()`
- Selects all columns explicitly
- Filters out rows where base fields (`user_id`, `session_id`, `timestamp`, `event_type`, `page`) are NULL

---

### Intermediate (`models/intermediate/`)

Models that do heavy transformations before the final marts.

#### `int_purchase_items`
**Why:** Purchase events store all purchased products inside a nested JSON array called `cart_items`. You can't directly aggregate revenue or count purchases per product from this. This model explodes the array into individual rows.

**What it does:**
- Filters `stg_events` for `event_type = 'purchase'`
- Uses Athena's `json_parse()` and `UNNEST()` to explode `cart_items` into one row per product
- Extracts `product_id`, `product_name`, `category`, `price`, `quantity` from each JSON element

**Example:**
```
Before (1 row):
purchase → cart_items: [{p018, Nintendo Switch, 349.99, qty:2}, {p026, Lululemon, 98.00, qty:1}]

After (2 rows):
row 1 → p018 | Nintendo Switch | Electronics | 349.99 | 2
row 2 → p026 | Lululemon Align Pant | Apparel | 98.00 | 1
```

---

### Marts (`models/marts/`)

Business-ready tables used directly by the dashboard.

#### `fct_sessions`
**Why:** Raw events have many rows per session. This collapses them into one row per session with useful metrics.

**What it does:**
- Groups by `user_id` and `session_id`
- Calculates `session_start` (MIN timestamp), `session_end` (MAX timestamp)
- Computes `session_duration_minutes` using `date_diff()`
- Counts total events per session
- Flags whether the session resulted in a purchase

---

#### `fct_funnel`
**Why:** The most important e-commerce metric — where are users dropping off in the purchase journey?

**What it does:**
- Counts how many sessions reached each funnel stage:
  - Sessions started → Viewed product → Added to cart → Reached checkout → Purchased
- Uses a CTE to first compute per-session flags, then aggregates across all sessions

---

#### `fct_product_performance`
**Why:** Understand which products drive views, cart additions, and revenue.

**What it does:**
- Pulls views and add-to-carts from `stg_events`
- Pulls purchases and revenue from `int_purchase_items` (correctly handles nested cart data)
- Joins both via `FULL OUTER JOIN` on `product_id`
- Calculates `total_revenue = SUM(price * quantity)`

**Why two sources?** Purchase events don't have individual product columns — they store everything in `cart_items`. Using `int_purchase_items` gives accurate per-product purchase counts and revenue.

---

#### `fct_search_analysis`
**Why:** Understand what users search for and whether those searches convert.

**What it does:**
- Extracts all search events with their queries and result counts
- Joins with session outcomes to determine if the session that contained the search also had a purchase
- Groups by `search_query` to get counts and conversion rates

---

#### `dim_customers`
**Why:** One row per customer with their complete lifetime history — useful for segmentation and understanding your customer base.

**What it does:**
- Joins three CTEs: `purchase_totals` (from `int_purchase_items`), `session_durations` (from `fct_sessions`), `favorite_category` (computed inline)
- Computes `favorite_category` using `ROW_NUMBER()` window function — ranks categories by interaction count per user and picks rank 1
- Aggregates spend, purchases, searches, coupon usage, abandonment

**Why CTEs?** Some metrics like `avg_session_duration_minutes` are already aggregated in `fct_sessions`. You can't `AVG()` an already-aggregated value in the same query level — CTEs let you pre-compute each metric separately then combine.

---

#### `fct_customer_segments`
**Why:** Classify every customer into a behavior segment for targeted analysis.

**What it does:**
- Reads from `dim_customers`
- Applies a priority-ordered `CASE WHEN` to assign one segment per user

**Segment rules (applied in order — first match wins):**

| Segment | Rule |
|---|---|
| High Value Buyer | `total_spent > 2000` |
| Coupon Hunter | `ever_used_coupon = 1` AND `total_purchases > 0` |
| Cart Abandoner | `ever_abandoned_checkout = 1` AND `total_purchases = 0` |
| Window Shopper | `total_purchases = 0` AND `ever_abandoned_checkout = 0` |
| Comparison Shopper | `total_searches >= 2` AND `total_purchases > 0` |
| Quick Buyer | `total_purchases > 0` AND `total_searches <= 1` |

---

## Data Quality Tests

49 tests defined across all models in `schema.yml` files.

| Test Type | What it checks |
|---|---|
| `not_null` | Critical columns never empty |
| `unique` | Primary keys have no duplicates |
| `accepted_values` | `event_type`, `payment_type`, `customer_segment`, `category` only contain valid values |

Run all tests:
```bash
dbt test
```

Run tests for a specific model:
```bash
dbt test --select stg_events
```

---

## Running the Project

```bash
# install adapter
pip install dbt-athena-community

# verify connection
dbt debug

# build all models
dbt run

# run all tests
dbt test

# build and test everything
dbt build
```

---

## Configuration

Connection settings are in `~/.dbt/profiles.yml` (not committed to git — contains AWS credentials).

Required fields:
```yaml
ecom_behavior:
  target: dev
  outputs:
    dev:
      type: athena
      region_name: eu-north-1
      s3_staging_dir: s3://your-bucket/athena-results/
      s3_data_dir: s3://your-bucket/dbt/
      database: awsdatacatalog
      schema: ecom_behavior_db
      aws_access_key_id: YOUR_KEY
      aws_secret_access_key: YOUR_SECRET
```