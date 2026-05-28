WITH purchase_totals AS (
    SELECT 
        user_id,
        SUM(quantity) AS total_products_purchased
    FROM {{ ref('int_purchase_items') }}
    GROUP BY user_id
),

session_durations AS (
    SELECT
        user_id,
        AVG(session_duration_minutes) AS avg_session_duration_minutes
    FROM {{ ref('fct_sessions') }}
    GROUP BY user_id
),

favorite_category AS (
    SELECT user_id, category AS favorite_category
    FROM (
        SELECT user_id, category, count(*) AS interaction_count,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY count(*) DESC) AS rn
        FROM {{ ref('stg_events') }}
        WHERE category IS NOT NULL 
        AND event_type IN ('open_product', 'like_product', 'add_to_cart')
        GROUP BY user_id, category
    )
    WHERE rn = 1
)

SELECT 
    S.user_id, 
    COUNT(DISTINCT session_id) AS total_sessions,
    SD.avg_session_duration_minutes AS avg_session_duration_minutes,
    MIN(timestamp) AS first_seen,
    MAX(timestamp) AS last_seen,
    COALESCE(PT.total_products_purchased, 0) AS total_products_purchased,
    COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) AS total_purchases,
    SUM(CASE WHEN event_type = 'purchase' THEN cart_total ELSE 0 END) AS total_spent,
    COUNT(CASE WHEN event_type = 'search' THEN 1 END) AS total_searches,
    MAX(CASE WHEN event_type = 'apply_coupon' THEN 1 ELSE 0 END) AS ever_used_coupon,
    MAX(CASE WHEN event_type = 'abandon_checkout' THEN 1 ELSE 0 END) AS ever_abandoned_checkout,
    FC.favorite_category AS favorite_category
    
FROM {{ ref('stg_events') }} S
LEFT JOIN purchase_totals PT on S.user_id = PT.user_id
LEFT JOIN session_durations SD ON S.user_id = SD.user_id 
LEFT JOIN favorite_category FC ON S.user_id = FC.user_id
GROUP BY S.user_id, PT.total_products_purchased, SD.avg_session_duration_minutes, FC.favorite_category

