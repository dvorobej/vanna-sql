with percent_rank <= 0.05
        PERCENT_RANK() OVER (
            PARTITION BY mcp.customer_home_store_id, mcp.country_id, mcp.month_start
            ORDER BY mcp.month_amount DESC
        ) AS pct_rank_within_store_country
    FROM monthly_customer_with_prev AS mcp
)
SELECT
    sc.customer_id,
    (SELECT c.h03 || ' ' || c.h04 FROM cus c WHERE c.h01 = sc.customer_id) AS customer_name,
    sc.country_name AS country,
    sc.city_name AS city,
    sc.customer_home_store_id AS store_id,
    strftime('%Y-%m', sc.month_start) AS payment_month,

    ROUND(sc.month_amount, 2) AS month_payment_amount,
    sc.payment_count,
    sc.distinct_staff_count,

    ROUND(
        sc.late_return_payment_count * 1.0 / NULLIF(sc.payment_count, 0),
        4
    ) AS late_return_payment_share,

    -- rank within store by month_amount
    RANK() OVER (
        PARTITION BY sc.customer_home_store_id, sc.month_start
        ORDER BY sc.month_amount DESC
    ) AS client_store_month_amount_rank
FROM store_country_ranked AS sc
WHERE sc.personal_avg_prev_months IS NOT NULL
  AND sc.personal_avg_prev_months > 0
  AND sc.month_amount >= 3.0 * sc.personal_avg_prev_months
  AND sc.pct_rank_within_store_country <= 0.05
ORDER BY
    sc.month_start,
    sc.customer_home_store_id,
    sc.month_amount DESC,
    sc.customer_id;