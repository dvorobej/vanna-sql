WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        c.h01,
        cty.d03 AS country_id
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    GROUP BY 1, 2, c.h01, cty.d03
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
        ) AS country_percentile
    FROM monthly_stats ms
),
country_medians AS (
    SELECT
        country_id,
        month,
        AVG(monthly_sum) AS median_monthly_sum
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY country_id, month ORDER BY monthly_sum) as rn,
                  COUNT(*) OVER (PARTITION BY country_id, month) as cnt
        FROM monthly_stats
    )
    WHERE rn IN (cnt/2, cnt/2 + 1)
    GROUP BY 1, 2
)
SELECT
    h.customer_id,
    h.month,
    h.monthly_sum,
    h.payment_count,
    h.staff_count,
    h.store_count,
    h.avg_prev_3_months,
    m.median_monthly_sum
FROM history_and_country h
JOIN country_medians m ON h.country_id = m.country_id AND h.month = m.month
WHERE h.avg_prev_3_months > 0
  AND h.monthly_sum >= 3 * h.avg_prev_3_months
  AND h.monthly_sum >= 2 * m.median_monthly_sum
  AND h.country_percentile <= 0.05
ORDER BY h.month DESC, h.monthly_sum DESC;