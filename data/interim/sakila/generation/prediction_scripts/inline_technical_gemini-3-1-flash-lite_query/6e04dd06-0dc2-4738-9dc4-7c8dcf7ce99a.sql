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
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
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
        ) AS country_percent_rank,
        (SELECT AVG(m2.monthly_sum) 
         FROM monthly_stats m2 
         WHERE m2.country_id = ms.country_id AND m2.month = ms.month) AS country_avg_sum
    FROM monthly_stats ms
),
country_medians AS (
    SELECT
        country_id,
        month,
        AVG(monthly_sum) AS median_monthly_sum
    FROM (
        SELECT country_id, month, monthly_sum,
               ROW_NUMBER() OVER (PARTITION BY country_id, month ORDER BY monthly_sum) as rn,
               COUNT(*) OVER (PARTITION BY country_id, month) as cnt
        FROM monthly_stats
    )
    WHERE rn IN (cnt/2, cnt/2 + 1)
    GROUP BY country_id, month
)
SELECT
    ms.customer_id,
    ms.month,
    ms.monthly_sum,
    ms.payment_count,
    ms.staff_count,
    ms.store_count,
    ms.avg_prev_3_months,
    cm.median_monthly_sum
FROM monthly_stats ms
JOIN history_and_country hc ON ms.customer_id = hc.customer_id AND ms.month = hc.month
JOIN country_medians cm ON ms.country_id = cm.country_id AND ms.month = cm.month
WHERE hc.avg_prev_3_months > 0
  AND ms.monthly_sum >= 3 * hc.avg_prev_3_months
  AND ms.monthly_sum >= 2 * cm.median_monthly_sum
  AND hc.country_percent_rank <= 0.05
ORDER BY ms.month DESC, ms.monthly_sum DESC;