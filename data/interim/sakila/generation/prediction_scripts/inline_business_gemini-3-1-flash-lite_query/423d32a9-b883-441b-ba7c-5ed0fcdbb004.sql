WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_stats AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_payments AS mp
),
filtered_months AS (
    SELECT
        ms.*,
        (ms.total_amount - ms.prev_avg_amount) AS deviation
    FROM monthly_stats AS ms
    WHERE ms.prev_avg_amount IS NOT NULL
      AND ms.total_amount >= 2 * ms.prev_avg_amount
      AND ms.payment_count >= 5
      AND (ms.staff_count > 1 OR ms.store_count > 1)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cn.c02 AS country,
        ct.d02 AS city,
        cn.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
),
ranked_deviations AS (
    SELECT
        fm.*,
        cg.country,
        cg.city,
        RANK() OVER (
            PARTITION BY cg.country_id, fm.payment_month
            ORDER BY fm.deviation DESC
        ) AS country_rank
    FROM filtered_months AS fm
    JOIN customer_geo AS cg ON cg.customer_id = fm.customer_id
)
SELECT
    payment_month,
    country,
    city,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(deviation, 2) AS deviation_from_prev_avg,
    country_rank
FROM ranked_deviations
ORDER BY payment_month, country, country_rank;