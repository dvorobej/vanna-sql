WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > r.q02 THEN 1.0 ELSE 0.0 END) / COUNT(*) AS late_return_share
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    GROUP BY 1, 2, 3, 4, 5, 6
),
history_stats AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_amount
    FROM monthly_payments
),
percentile_stats AS (
    SELECT
        *,
        PERCENT_RANK() OVER (
            PARTITION BY store_id, country_id, payment_month
            ORDER BY total_amount
        ) AS p_rank
    FROM history_stats
),
ranked_results AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY country_id, payment_month
            ORDER BY total_amount DESC
        ) AS country_rank
    FROM percentile_stats
    WHERE avg_prev_amount IS NOT NULL
      AND total_amount > 3 * avg_prev_amount
      AND p_rank >= 0.95
)
SELECT
    country_name,
    city_name,
    store_id,
    payment_month,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    staff_count,
    ROUND(late_return_share, 4) AS late_return_share,
    country_rank
FROM ranked_results
ORDER BY
    payment_month DESC,
    country_name,
    country_rank;