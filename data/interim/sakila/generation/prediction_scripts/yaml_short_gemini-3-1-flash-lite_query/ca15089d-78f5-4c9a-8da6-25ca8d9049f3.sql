WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT date(p.p06)) AS distinct_days,
        COUNT(DISTINCT p.p03) AS distinct_staff,
        COUNT(DISTINCT s.o07) AS distinct_stores,
        MAX(p.p05) AS max_payment
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
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
        mwh.*,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id
    FROM monthly_with_history AS mwh
    JOIN cus AS c ON c.h01 = mwh.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    WHERE mwh.prev_avg_monthly_sum IS NOT NULL
      AND mwh.monthly_sum >= 3 * mwh.prev_avg_monthly_sum
      AND mwh.payment_count >= 3
      AND mwh.distinct_days >= 3
      AND (mwh.distinct_staff >= 2 OR mwh.distinct_stores >= 2)
)
SELECT
    payment_month,
    first_name || ' ' || last_name AS full_name,
    country,
    city,
    payment_count,
    ROUND(monthly_sum, 2) AS monthly_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / NULLIF(monthly_sum, 0), 4) AS max_payment_share,
    distinct_staff,
    distinct_stores,
    RANK() OVER (
        PARTITION BY country_id, payment_month
        ORDER BY monthly_sum DESC
    ) AS country_rank
FROM suspicious_clients
ORDER BY
    payment_month DESC,
    country,
    country_rank;