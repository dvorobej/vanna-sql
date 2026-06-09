WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT date(p.p06)) AS distinct_days,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff,
        COUNT(DISTINCT s.j01) AS distinct_stores
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN sto AS s ON c.h02 = s.j01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        *,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_stats
),
filtered_clients AS (
    SELECT *
    FROM history_stats
    WHERE prev_avg_sum IS NOT NULL
      AND monthly_sum > 3 * prev_avg_sum
      AND payment_count >= 3
      AND (distinct_staff >= 3 OR distinct_stores >= 3)
)
SELECT
    fc.payment_month,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    fc.payment_count,
    fc.monthly_sum,
    fc.max_payment,
    ROUND(fc.max_payment / NULLIF(fc.monthly_sum, 0), 4) AS max_payment_share,
    fc.distinct_staff,
    fc.distinct_stores,
    RANK() OVER (
        PARTITION BY cnt.c01, fc.payment_month 
        ORDER BY fc.monthly_sum DESC
    ) AS country_rank
FROM filtered_clients AS fc
JOIN cus AS c ON fc.customer_id = c.h01
JOIN adr ON c.h06 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
ORDER BY cnt.c02, fc.payment_month, fc.monthly_sum DESC;