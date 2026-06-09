WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        c.h02 AS home_store_id,
        cnt.c01 AS country_id
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt ON ci.d03 = cnt.c01
    GROUP BY 1, 2, 7, 8
),
history_and_country AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.month 
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months,
        PERCENT_RANK() OVER (
            PARTITION BY ms.country_id, ms.month 
            ORDER BY ms.monthly_sum DESC
        ) AS country_percentile,
        (SELECT AVG(m2.monthly_sum) 
         FROM (SELECT monthly_sum, country_id, month FROM monthly_stats) m2
         WHERE m2.country_id = ms.country_id AND m2.month = ms.month
         ORDER BY m2.monthly_sum 
         LIMIT 1 OFFSET (SELECT COUNT(*) FROM monthly_stats m3 WHERE m3.country_id = ms.country_id AND m3.month = ms.month) / 2
        ) AS country_median_sum
    FROM monthly_stats ms
)
SELECT
    customer_id,
    month,
    monthly_sum,
    payment_count,
    staff_count,
    store_count
FROM history_and_country
WHERE monthly_sum >= 3 * COALESCE(avg_prev_3_months, 0)
  AND monthly_sum >= 2 * COALESCE(country_median_sum, 0)
  AND country_percentile <= 0.05
ORDER BY month DESC, monthly_sum DESC;