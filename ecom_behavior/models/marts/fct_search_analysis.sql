WITH search_events AS (
    SELECT 
        session_id,
        search_query,
        results_count
    FROM {{ ref('stg_events') }}
    WHERE event_type = 'search'
),

session_outcomes AS (
    SELECT
        session_id,
        MAX(CASE WHEN event_type = 'open_product' THEN 1 ELSE 0 END) AS had_view,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS had_purchase
    FROM {{ ref('stg_events') }}
    GROUP BY session_id
)

SELECT
    s.search_query,
    COUNT(*) AS search_count,
    ROUND(AVG(s.results_count), 0) AS avg_results,
    SUM(o.had_view) AS led_to_view,
    SUM(o.had_purchase) AS led_to_purchase
FROM search_events s
JOIN session_outcomes o ON s.session_id = o.session_id
GROUP BY s.search_query
ORDER BY search_count DESC