SELECT user_id, session_id, CAST(date_parse(timestamp, '%Y-%m-%dT%H:%i:%s.%f') AS TIMESTAMP) AS timestamp, event_type, page, product_id, product_name, category, price, quantity, search_query, results_count, source, cart_value, abandonment_stage, items_count, coupon_code, discount_percentage, filter_type, payment_type, cart_items, cart_total FROM {{ source('ecom_behavior', 'events') }}
WHERE user_id IS NOT NULL
AND session_id IS NOT NULL
AND timestamp IS NOT NULL
AND event_type IS NOT NULL
AND page IS NOT NULL;