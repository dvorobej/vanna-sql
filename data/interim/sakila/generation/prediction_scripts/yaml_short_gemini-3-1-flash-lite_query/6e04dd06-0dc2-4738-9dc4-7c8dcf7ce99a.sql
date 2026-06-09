WITH monthly_stats AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.j01) AS store_count
    FROM cus c
    JOIN pay p ON c.h01 = p.p02
    JOIN stf st ON p.p03 = st.o01
    JOIN sto s ON st.o07 = s.j01
    JOIN adr a ON s.j03 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt ON ci.d03 = cnt.c01
    GROUP BY c.h01, payment_month
),
history_and_country AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months,
        PERCENT_RANK() OVER (
            PARTITION BY ms.payment_month, ms.country_id 
            ORDER BY ms.monthly_sum DESC
        ) AS country_percent_rank
    FROM monthly_stats ms
),
country_medians AS (
    SELECT
        payment_month,
        country_id,
        AVG(monthly_sum) AS median_monthly_sum
    FROM (
        SELECT 
            payment_month, country_id, monthly_sum,
            ROW_NUMBER() OVER (PARTITION BY payment_month, country_id ORDER BY monthly_sum) as rn,
            COUNT(*) OVER (PARTITION BY payment_month, country_id) as cnt
        FROM monthly_stats
    )
    WHERE rn IN (cnt/2, cnt/2 + 1)
    GROUP BY payment_month, country_id
)
SELECT
    h.customer_id,
    h.customer_name,
    h.country_name,
    h.payment_month,
    h.monthly_sum,
    h.payment_count,
    h.staff_count,
    h.store_count,
    h.avg_prev_3_months,
    m.median_monthly_sum
FROM history_and_country h
JOIN country_medians m ON h.payment_month = m.payment_month AND h.country_id = m.country_id
WHERE h.avg_prev_3_months > 0
  AND h.monthly_sum >= 3 * h.avg_prev_3_months
  AND h.monthly_sum >= 2 * m.median_monthly_sum
  AND h.country_percent_rank <= 0.05
ORDER BY h.payment_month DESC, h.monthly_sum DESC;