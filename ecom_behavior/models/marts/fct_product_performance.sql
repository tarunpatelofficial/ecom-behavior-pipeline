WITH product_interactions AS (
    -- views and add_to_carts from stg_events
    SELECT product_id, product_name, category,
        COUNT(CASE WHEN event_type = 'open_product' THEN 1 END) AS views,
        COUNT(CASE WHEN event_type = 'add_to_cart' THEN 1 END) AS add_to_carts
    FROM {{ ref('stg_events') }}
    WHERE event_type IN ('open_product', 'add_to_cart')
    AND product_id IS NOT NULL
    GROUP BY product_id, product_name, category
),

product_purchases AS (
    -- purchases and revenue from int_purchase_items
    SELECT product_id, product_name, category,
        COUNT(*) AS purchases,
        SUM(price * quantity) AS total_revenue
    FROM {{ ref('int_purchase_items') }}
    GROUP BY product_id, product_name, category
)

SELECT
    COALESCE(i.product_id, p.product_id) AS product_id,
    COALESCE(i.product_name, p.product_name) AS product_name,
    COALESCE(i.category, p.category) AS category,
    COALESCE(i.views, 0) AS views,
    COALESCE(i.add_to_carts, 0) AS add_to_carts,
    COALESCE(p.purchases, 0) AS purchases,
    COALESCE(p.total_revenue, 0) AS total_revenue
FROM product_interactions i
FULL OUTER JOIN product_purchases p ON i.product_id = p.product_id