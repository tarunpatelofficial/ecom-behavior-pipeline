SELECT
    user_id,
    CASE 
        WHEN total_spent > 2000 THEN 'High Value Buyer'
        WHEN ever_used_coupon = 1 AND total_purchases > 0 THEN 'Coupon Hunter'
        WHEN ever_abandoned_checkout = 1 AND total_purchases = 0 THEN 'Cart Abandoner'
        WHEN total_purchases = 0 AND ever_abandoned_checkout = 0 THEN 'Window Shopper'
        WHEN total_searches >= 2 AND total_purchases > 0 THEN 'Comparison Shopper'
        WHEN total_purchases > 0 AND total_searches <= 1 THEN 'Quick Buyer'
        ELSE 'Uncategorized'
    END AS customer_segment
FROM {{ ref('dim_customers') }}