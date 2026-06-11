WITH monthly_stats AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS store_id,
        co.c02 AS country_name,
        co.c01 AS country_id,
        strftime('%Y-%m', p.p06) AS month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS total_amount,
        AVG(p.p05) AS avg_check,
        COUNT(DISTINCT date(p.p06)) AS active_days
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    GROUP BY 1, 2, 3, 4, 5, 6
),
monthly_comparison AS (
    SELECT
        ms.*,
        LAG(ms.total_amount) OVER (PARTITION BY ms.customer_id ORDER BY ms.month) AS prev_month_amount,
        AVG(ms.total_amount) OVER (PARTITION BY ms.country_id, ms.month) AS country_avg_amount
    FROM monthly_stats ms
),
top_staff_per_month AS (
    SELECT customer_id, month, staff_id, staff_name
    FROM (
        SELECT 
            p.p02 AS customer_id, 
            strftime('%Y-%m', p.p06) AS month, 
            p.p03 AS staff_id, 
            s.o02 || ' ' || s.o03 AS staff_name,
            SUM(p.p05) AS staff_sum,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        JOIN stf s ON p.p03 = s.o01
        GROUP BY 1, 2, 3
    ) WHERE rn = 1
)
SELECT
    mc.customer_id,
    mc.customer_name,
    mc.country_name,
    mc.store_id,
    mc.month,
    mc.total_amount,
    mc.payment_count,
    mc.avg_check,
    mc.active_days,
    ts.staff_name AS top_staff_name,
    RANK() OVER (PARTITION BY mc.country_id, mc.month ORDER BY mc.total_amount DESC) AS country_rank
FROM monthly_comparison mc
JOIN top_staff_per_month ts ON mc.customer_id = ts.customer_id AND mc.month = ts.month
WHERE (mc.prev_month_amount IS NOT NULL AND mc.total_amount >= 3 * mc.prev_month_amount)
   OR (mc.total_amount > 2 * mc.country_avg_amount)
ORDER BY mc.month DESC, mc.total_amount DESC;