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
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
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
    FROM monthly_stats AS ms
),
suspicious_clients AS (
    SELECT
        hs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country,
        ct.d02 AS city,
        co.c01 AS country_id
    FROM history_stats AS hs
    JOIN cus AS c ON c.h01 = hs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ct.d03
    WHERE hs.prev_avg_monthly_sum IS NOT NULL
      AND hs.monthly_sum >= 3 * hs.prev_avg_monthly_sum
      AND hs.payment_count >= 3
      AND hs.distinct_days >= 3
      AND (hs.distinct_staff > 1 OR hs.distinct_stores > 1)
)
SELECT
    sc.payment_month,
    sc.customer_name,
    sc.country,
    sc.city,
    sc.payment_count,
    ROUND(sc.monthly_sum, 2) AS monthly_sum,
    ROUND(sc.max_payment, 2) AS max_payment,
    ROUND(sc.max_payment / NULLIF(sc.monthly_sum, 0), 4) AS max_payment_share,
    sc.distinct_staff,
    sc.distinct_stores,
    RANK() OVER (
        PARTITION BY sc.country_id, sc.payment_month
        ORDER BY sc.monthly_sum DESC
    ) AS country_rank
FROM suspicious_clients AS sc
ORDER BY
    sc.payment_month DESC,
    sc.country,
    country_rank;