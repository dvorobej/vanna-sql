WITH monthly_metrics AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.j01) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN sto AS s ON s.j01 = c.h02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_metrics AS (
    SELECT
        *,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_metrics
),
filtered_clients AS (
    SELECT *
    FROM history_metrics
    WHERE prev_avg_sum IS NOT NULL
      AND monthly_sum > 3 * prev_avg_sum
      AND payment_count >= 3
      AND (distinct_staff_count >= 3 OR distinct_store_count >= 3)
),
ranked_clients AS (
    SELECT
        fc.*,
        c.h03 || ' ' || c.h04 AS full_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        RANK() OVER (
            PARTITION BY cnt.c01, fc.payment_month 
            ORDER BY fc.monthly_sum DESC
        ) AS country_rank
    FROM filtered_clients AS fc
    JOIN cus AS c ON c.h01 = fc.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
)
SELECT
    payment_month,
    full_name,
    country_name,
    city_name,
    payment_count,
    ROUND(monthly_sum, 2) AS total_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / NULLIF(monthly_sum, 0), 4) AS max_payment_share,
    distinct_staff_count,
    distinct_store_count,
    country_rank
FROM ranked_clients
ORDER BY country_name, payment_month, monthly_sum DESC;