WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_avg AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_stats AS ms
),
filtered_clients AS (
    SELECT
        mwa.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cn.c02 AS country,
        ct.d02 AS city,
        cn.c01 AS country_id,
        (mwa.monthly_sum - mwa.prev_avg_sum) AS deviation
    FROM monthly_with_avg AS mwa
    JOIN cus AS c ON c.h01 = mwa.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    WHERE mwa.prev_avg_sum IS NOT NULL
      AND mwa.monthly_sum >= 2 * mwa.prev_avg_sum
      AND mwa.payment_count >= 5
      AND (mwa.staff_count >= 2 OR mwa.store_count >= 2)
),
ranked_deviations AS (
    SELECT
        fc.*,
        RANK() OVER (
            PARTITION BY fc.country_id, fc.payment_month
            ORDER BY fc.deviation DESC
        ) AS country_deviation_rank
    FROM filtered_clients AS fc
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    ROUND(monthly_sum, 2) AS monthly_sum,
    payment_count,
    ROUND(deviation, 2) AS deviation_from_prev_avg,
    country_deviation_rank
FROM ranked_deviations
ORDER BY
    payment_month,
    country,
    country_deviation_rank;