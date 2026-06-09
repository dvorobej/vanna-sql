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
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    GROUP BY 1, 2, 3, 4, 5, 6
),
prev_month_stats AS (
    SELECT
        *,
        LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY payment_month) AS prev_month_amount,
        AVG(total_amount) OVER (PARTITION BY country_id, payment_month) AS country_avg_amount
    FROM monthly_stats
),
staff_top AS (
    SELECT
        customer_id,
        payment_month,
        staff_id,
        ROW_NUMBER() OVER (PARTITION BY customer_id, payment_month ORDER BY staff_sum DESC) as rn
    FROM (
        SELECT p.p02 AS customer_id, strftime('%Y-%m', p.p06) AS payment_month, p.p03 AS staff_id, SUM(p.p05) AS staff_sum
        FROM pay p
        GROUP BY 1, 2, 3
    )
),
ranked_clients AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_id, payment_month ORDER BY total_amount DESC) AS country_rank
    FROM prev_month_stats
)
SELECT
    rc.customer_name,
    rc.country_name,
    rc.store_id,
    rc.payment_month,
    rc.total_amount,
    rc.payment_count,
    rc.avg_check,
    rc.active_days,
    rc.country_rank,
    st.staff_id AS top_staff_id
FROM ranked_clients rc
JOIN staff_top st ON rc.customer_id = st.customer_id AND rc.payment_month = st.payment_month AND st.rn = 1
WHERE (rc.prev_month_amount IS NOT NULL AND rc.total_amount >= 3 * rc.prev_month_amount)
   OR (rc.total_amount > 2 * rc.country_avg_amount)
ORDER BY rc.payment_month DESC, rc.country_rank ASC;