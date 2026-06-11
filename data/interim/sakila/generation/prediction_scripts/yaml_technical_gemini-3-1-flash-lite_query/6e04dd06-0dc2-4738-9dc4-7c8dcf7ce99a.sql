WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.j01) AS store_count,
        c.h02 AS home_store_id,
        cnt.c01 AS country_id
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN sto s ON c.h02 = s.j01
    JOIN adr a ON s.j03 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt ON ci.d03 = cnt.c01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months,
        PERCENT_RANK() OVER (
            PARTITION BY ms.country_id, ms.payment_month 
            ORDER BY ms.monthly_sum DESC
        ) AS country_percentile
    FROM monthly_stats ms
),
country_medians AS (
    SELECT
        country_id,
        payment_month,
        AVG(monthly_sum) AS median_monthly_sum
    FROM (
        SELECT 
            country_id, payment_month, monthly_sum,
            ROW_NUMBER() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_sum) as rn,
            COUNT(*) OVER (PARTITION BY country_id, payment_month) as cnt
        FROM monthly_stats
    )
    WHERE rn IN (cnt/2, cnt/2 + 1)
    GROUP BY country_id, payment_month
)
SELECT
    hs.customer_id,
    hs.payment_month,
    hs.monthly_sum,
    hs.payment_count,
    hs.staff_count,
    hs.store_count,
    hs.avg_prev_3_months,
    cm.median_monthly_sum
FROM history_stats hs
JOIN country_medians cm ON hs.country_id = cm.country_id AND hs.payment_month = cm.payment_month
WHERE hs.avg_prev_3_months > 0
  AND hs.monthly_sum >= 3 * hs.avg_prev_3_months
  AND hs.monthly_sum >= 2 * cm.median_monthly_sum
  AND hs.country_percentile <= 0.05
ORDER BY hs.payment_month DESC, hs.monthly_sum DESC;