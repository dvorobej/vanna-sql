WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT date(p.p06)) AS distinct_days,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_months
    FROM monthly_stats AS ms
),
filtered_customers AS (
    SELECT
        mwh.*,
        c.h03 || ' ' || c.h04 AS full_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id
    FROM monthly_with_history AS mwh
    JOIN cus AS c ON c.h01 = mwh.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    WHERE mwh.avg_prev_months > 0
      AND mwh.monthly_sum > 3 * mwh.avg_prev_months
      AND mwh.payment_count >= 3
      AND mwh.distinct_days >= 3
)
SELECT
    month,
    full_name,
    country,
    city,
    payment_count,
    ROUND(monthly_sum, 2) AS monthly_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / monthly_sum, 4) AS max_payment_share,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id, month
        ORDER BY monthly_sum DESC
    ) AS country_rank
FROM filtered_customers
ORDER BY month, country, country_rank;