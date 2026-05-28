WITH fct_session_behavior AS (
SELECT
    user_id,
    session_id,

    MAX(CASE WHEN event_type = 'login' THEN 1 ELSE 0 END) AS did_login,
    MAX(CASE WHEN event_type = 'open_product' THEN 1 ELSE 0 END) AS did_open_product,
    MAX(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) AS did_add_to_cart,
    MAX(CASE WHEN event_type = 'choose_payment_method' THEN 1 ELSE 0 END) AS did_choose_payment,
    MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS did_purchase,

    COUNT(CASE WHEN event_type = 'search' THEN 1 END) AS searches,
    COUNT(CASE WHEN event_type = 'apply_filters' THEN 1 END) AS filters_used,
    COUNT(CASE WHEN event_type = 'like_product' THEN 1 END) AS liked_products,

    COUNT(CASE WHEN event_type = 'add_to_cart' THEN 1 END) AS add_to_cart_count,
    COUNT(CASE WHEN event_type = 'remove_from_cart' THEN 1 END) AS remove_from_cart_count,

    MAX(CASE WHEN event_type = 'apply_coupon' THEN 1 ELSE 0 END) AS used_coupon,

    MAX(CASE WHEN event_type = 'abandon_checkout' THEN 1 ELSE 0 END) AS abandoned_checkout,

    MIN(CAST(timestamp AS TIMESTAMP)) AS session_start,
    MAX(CAST(timestamp AS TIMESTAMP)) AS session_end

FROM {{ ref('stg_events') }}

GROUP BY user_id, session_id
)

SELECT
    SUM(did_login) AS sessions_started,
    SUM(did_open_product) AS viewed_product,
    SUM(did_add_to_cart) AS added_to_cart,
    SUM(did_choose_payment) AS reached_checkout,
    SUM(did_purchase) AS purchased,
    SUM(abandoned_checkout) AS abandoned_checkout
FROM fct_session_behavior