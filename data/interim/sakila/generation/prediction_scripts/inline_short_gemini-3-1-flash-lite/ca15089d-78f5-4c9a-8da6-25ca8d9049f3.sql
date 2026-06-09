WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT date(p.p06)) AS distinct_days,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        c.h03 || ' ' || c.h04 AS full_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN stf AS s ON p.p03 = s.o01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_avg AS (
    SELECT
        *,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id
            ORDER BY month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_stats
),
filtered_clients AS (
    SELECT
        *,
        (max_payment / monthly_sum) AS max_payment_share
    FROM monthly_with_avg
    WHERE prev_avg_sum IS NOT NULL
      AND monthly_sum > 3 * prev_avg_sum
      AND payment_count >= 3
      AND distinct_days >= 3
)
SELECT
    month,
    full_name,
    country,
    city,
    payment_count,
    ROUND(monthly_sum, 2) AS monthly_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment_share, 4) AS max_payment_share,
    staff_count,
    store_count,
    RANK() OVER (PARTITION BY country, month ORDER BY monthly_sum DESC) AS country_rank
FROM filtered_clients
ORDER BY month DESC, country, country_rank;