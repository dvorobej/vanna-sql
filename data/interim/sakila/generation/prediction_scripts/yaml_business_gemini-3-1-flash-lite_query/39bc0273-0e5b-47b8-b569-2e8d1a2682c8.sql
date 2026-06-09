WITH monthly_stats AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS store_id,
        co.c02 AS country_name,
        co.c01 AS country_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS total_amount,
        AVG(p.p05) AS avg_check,
        COUNT(DISTINCT date(p.p06)) AS active_days
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
    GROUP BY 1, 2, 3, 4, 5, 6
),
monthly_comparison AS (
    SELECT
        ms.*,
        LAG(ms.total_amount) OVER (PARTITION BY ms.customer_id ORDER BY ms.payment_month) AS prev_month_amount,
        AVG(ms.total_amount) OVER (PARTITION BY ms.country_id, ms.payment_month) AS country_avg_amount,
        RANK() OVER (PARTITION BY ms.country_id, ms.payment_month ORDER BY ms.total_amount DESC) AS country_rank
    FROM monthly_stats ms
),
top_staff AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        s.o02 || ' ' || s.o03 AS staff_name,
        SUM(p.p05) AS staff_total,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) AS rn
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    GROUP BY 1, 2, 3
)
SELECT
    mc.customer_id,
    mc.customer_name,
    mc.country_name,
    mc.store_id,
    mc.payment_month,
    mc.total_amount,
    mc.payment_count,
    mc.avg_check,
    mc.active_days,
    mc.country_rank,
    ts.staff_name AS top_staff_name
FROM monthly_comparison mc
JOIN top_staff ts ON ts.customer_id = mc.customer_id AND ts.payment_month = mc.payment_month AND ts.rn = 1
WHERE (mc.prev_month_amount IS NOT NULL AND mc.total_amount >= 3 * mc.prev_month_amount)
   OR (mc.total_amount > 2 * mc.country_avg_amount)
ORDER BY mc.payment_month DESC, mc.country_rank ASC;