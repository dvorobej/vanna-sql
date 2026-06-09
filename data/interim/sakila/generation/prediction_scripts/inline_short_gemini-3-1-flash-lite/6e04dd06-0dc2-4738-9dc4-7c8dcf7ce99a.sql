WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        c.h02 AS home_store_id,
        co.c01 AS country_id,
        co.c02 AS country_name
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    GROUP BY p.p02, strftime('%Y-%m', p.p06), c.h02, co.c01, co.c02
),
history_and_median AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (PARTITION BY ms.customer_id ORDER BY ms.payment_month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS prev_avg_sum,
        (SELECT AVG(m.monthly_sum) FROM (
            SELECT monthly_sum, country_id, payment_month,
                   ROW_NUMBER() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_sum) as rn,
                   COUNT(*) OVER (PARTITION BY country_id, payment_month) as cnt
            FROM monthly_stats
        ) m WHERE m.country_id = ms.country_id AND m.payment_month = ms.payment_month AND m.rn BETWEEN m.cnt/2.0 AND m.cnt/2.0 + 1) AS country_median_sum,
        PERCENT_RANK() OVER (PARTITION BY ms.country_id, ms.payment_month ORDER BY ms.monthly_sum) AS country_percentile
    FROM monthly_stats ms
)
SELECT
    customer_id,
    payment_month,
    country_name,
    monthly_sum,
    payment_count,
    staff_count,
    store_count,
    prev_avg_sum,
    country_median_sum
FROM history_and_median
WHERE monthly_sum >= 3.0 * COALESCE(prev_avg_sum, 0)
  AND monthly_sum >= 2.0 * COALESCE(country_median_sum, 0)
  AND country_percentile >= 0.95
ORDER BY payment_month DESC, monthly_sum DESC;