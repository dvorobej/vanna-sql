WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS store_id,
        ct.d03 AS country_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > r.q02 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS late_return_share
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    LEFT JOIN ren r ON p.p04 = r.q01
    GROUP BY 1, 2, 3, 4
),
history_stats AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_amount
    FROM monthly_customer_stats
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
ranked_stats AS (
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
    cnt.c02 AS country,
    ct.d02 AS city,
    rs.store_id,
    rs.payment_month,
    ROUND(rs.total_amount, 2) AS total_amount,
    rs.payment_count,
    rs.staff_count,
    ROUND(rs.late_return_share, 4) AS late_return_share,
    rs.country_rank
FROM ranked_stats rs
JOIN cnt cnt ON rs.country_id = cnt.c01
JOIN cus c ON rs.customer_id = c.h01
JOIN adr a ON c.h06 = a.e01
JOIN cty ct ON a.e05 = ct.d01
ORDER BY rs.payment_month DESC, rs.country_rank ASC;