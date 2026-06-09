WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS total_amount,
        AVG(p.p05) AS avg_payment,
        COUNT(DISTINCT date(p.p06)) AS active_days
    FROM pay p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_context AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        co.c02 AS country_name,
        co.c01 AS country_id
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
),
staff_preference AS (
    SELECT customer_id, payment_month, staff_id,
           ROW_NUMBER() OVER (PARTITION BY customer_id, payment_month ORDER BY total_staff_amount DESC) as rn
    FROM (
        SELECT p.p02 AS customer_id, strftime('%Y-%m', p.p06) AS payment_month, p.p03 AS staff_id, SUM(p.p05) AS total_staff_amount
        FROM pay p GROUP BY 1, 2, 3
    )
),
comparison AS (
    SELECT
        ms.*,
        cc.store_id,
        cc.country_name,
        cc.country_id,
        LAG(ms.total_amount) OVER (PARTITION BY ms.customer_id ORDER BY ms.payment_month) AS prev_month_amount,
        AVG(ms.total_amount) OVER (PARTITION BY cc.country_id, ms.payment_month) AS country_avg_amount
    FROM monthly_stats ms
    JOIN customer_context cc ON ms.customer_id = cc.customer_id
),
ranked_clients AS (
    SELECT *,
           RANK() OVER (PARTITION BY country_id, payment_month ORDER BY total_amount DESC) AS country_rank
    FROM comparison
)
SELECT
    rc.customer_id,
    rc.payment_month,
    rc.total_amount,
    rc.payment_count,
    rc.avg_payment,
    rc.country_name,
    rc.store_id,
    s.staff_id AS top_staff_id,
    rc.country_rank
FROM ranked_clients rc
JOIN staff_preference s ON rc.customer_id = s.customer_id AND rc.payment_month = s.payment_month AND s.rn = 1
WHERE (rc.total_amount > 2 * rc.prev_month_amount AND rc.prev_month_amount > 0)
   OR (rc.total_amount > 1.5 * rc.country_avg_amount)
ORDER BY rc.payment_month DESC, rc.total_amount DESC;