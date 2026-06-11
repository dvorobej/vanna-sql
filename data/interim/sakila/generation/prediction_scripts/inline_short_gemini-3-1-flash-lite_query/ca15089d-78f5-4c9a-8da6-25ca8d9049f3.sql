WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT DATE(p.p06)) AS distinct_days,
        COUNT(DISTINCT p.p03) AS distinct_staff,
        COUNT(DISTINCT s.o07) AS distinct_stores,
        MAX(p.p05) AS max_payment
    FROM pay p
    JOIN stf s ON p.p03 = s.o01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_monthly_sum
    FROM monthly_stats ms
),
suspicious_clients AS (
    SELECT
        hs.*,
        c.h03 || ' ' || c.h04 AS full_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        RANK() OVER (PARTITION BY cnt.c01, hs.payment_month ORDER BY hs.monthly_sum DESC) AS country_rank
    FROM history_stats hs
    JOIN cus c ON hs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty cty ON a.e05 = cty.d01
    JOIN cnt cnt ON cty.d03 = cnt.c01
    WHERE hs.prev_avg_monthly_sum IS NOT NULL
      AND hs.monthly_sum >= 3 * hs.prev_avg_monthly_sum
      AND hs.payment_count >= 3
      AND hs.distinct_days >= 3
      AND (hs.distinct_staff >= 2 OR hs.distinct_stores >= 2)
)
SELECT
    payment_month,
    full_name,
    country,
    city,
    payment_count,
    ROUND(monthly_sum, 2) AS monthly_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / NULLIF(monthly_sum, 0), 4) AS max_payment_share,
    distinct_staff,
    distinct_stores,
    country_rank
FROM suspicious_clients
ORDER BY payment_month, country, country_rank;