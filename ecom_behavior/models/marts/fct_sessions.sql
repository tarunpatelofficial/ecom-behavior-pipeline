WITH session_events AS (
    SELECT
        user_id,
        session_id,
        count(*) as Event_Count,

        MIN(timestamp) AS session_start,
        MAX(timestamp) AS session_end,

        MAX(
            CASE
                WHEN event_type = 'purchase' THEN 1
                ELSE 0
            END
        ) AS did_purchase

    FROM {{ ref('stg_events') }}

    GROUP BY user_id, session_id
)

SELECT *,
       date_diff('minute', session_start, session_end) AS session_duration_minutes
FROM session_events