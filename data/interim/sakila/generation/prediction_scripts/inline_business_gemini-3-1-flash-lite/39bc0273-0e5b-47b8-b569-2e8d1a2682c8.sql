WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
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
monthly_history AS (
    SELECT
        *,
        LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY payment_month) AS prev_month_amount,
        AVG(total_amount) OVER (PARTITION BY country_id, payment_month) AS country_avg_amount
    FROM monthly_stats
),
top_staff AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        s.o02 || ' ' || s.o03 AS staff_name,
        COUNT(*) AS staff_ops,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY COUNT(*) DESC) AS rn
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    GROUP BY 1, 2, 3
),
ranked_clients AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_id, payment_month ORDER BY total_amount DESC) AS country_rank
    FROM monthly_history
)
SELECT
    rc.customer_id,
    rc.customer_name,
    rc.country_name,
    rc.store_id,
    rc.payment_month,
    rc.total_amount,
    rc.payment_count,
    rc.avg_check,
    rc.active_days,
    rc.country_rank,
    ts.staff_name AS top_staff_name
FROM ranked_clients rc
JOIN top_staff ts ON ts.customer_id = rc.customer_id AND ts.payment_month = rc.payment_month AND ts.rn = 1
WHERE (rc.total_amount > 2 * rc.prev_month_amount AND rc.prev_month_amount > 0)
   OR (rc.total_amount > 1.5 * rc.country_avg_amount)
ORDER BY rc.payment_month DESC, rc.total_amount DESC;