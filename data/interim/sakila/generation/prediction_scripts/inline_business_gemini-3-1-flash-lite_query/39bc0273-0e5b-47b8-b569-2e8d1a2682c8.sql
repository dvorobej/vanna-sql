WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS month,
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
prev_month_stats AS (
    SELECT
        ms.*,
        LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY month) AS prev_month_amount,
        AVG(total_amount) OVER (PARTITION BY country_id, month) AS country_avg_amount
    FROM monthly_stats ms
),
staff_top AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        p.p03 AS staff_id,
        s.o02 || ' ' || s.o03 AS staff_name,
        SUM(p.p05) AS staff_sum,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) AS rn
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    GROUP BY 1, 2, 3
),
ranked_clients AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_id, month ORDER BY total_amount DESC) AS country_rank
    FROM prev_month_stats
    WHERE (prev_month_amount IS NOT NULL AND total_amount >= 3 * prev_month_amount)
       OR (total_amount > 2 * country_avg_amount)
)
SELECT
    rc.customer_id,
    rc.customer_name,
    rc.country_name,
    rc.store_id,
    rc.month,
    rc.total_amount,
    rc.payment_count,
    rc.avg_check,
    rc.active_days,
    rc.country_rank,
    st.staff_name AS top_staff_name
FROM ranked_clients rc
JOIN staff_top st ON st.customer_id = rc.customer_id AND st.month = rc.month AND st.rn = 1
ORDER BY rc.month DESC, rc.country_name, rc.country_rank;