SELECT
    user_id,
    session_id,
    timestamp,
    json_extract_scalar(item, '$.product_id') AS product_id,
    json_extract_scalar(item, '$.product_name') AS product_name,
    json_extract_scalar(item, '$.category') AS category,
    CAST(json_extract_scalar(item, '$.price') AS DOUBLE) AS price,
    CAST(json_extract_scalar(item, '$.quantity') AS INTEGER) AS quantity
FROM {{ ref('stg_events') }}
CROSS JOIN UNNEST(CAST(json_parse(cart_items) AS ARRAY(JSON))) AS t(item)
WHERE event_type = 'purchase'
AND cart_items IS NOT NULL