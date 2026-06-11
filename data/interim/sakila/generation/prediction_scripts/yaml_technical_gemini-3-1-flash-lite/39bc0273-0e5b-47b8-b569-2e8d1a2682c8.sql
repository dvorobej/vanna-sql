WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        AVG(p.p05) AS avg_check,
        COUNT(DISTINCT date(p.p06)) AS distinct_payment_days
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
monthly_with_history AS (
    SELECT
        mcs.*,
        cg.store_id,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        LAG(mcs.monthly_amount) OVER (PARTITION BY mcs.customer_id ORDER BY mcs.payment_month) AS prev_month_amount
    FROM monthly_customer_stats AS mcs
    JOIN customer_geo AS cg ON cg.customer_id = mcs.customer_id
),
country_monthly_avg AS (
    SELECT
        country_id,
        payment_month,
        AVG(monthly_amount) AS country_avg_amount
    FROM monthly_with_history
    GROUP BY country_id, payment_month
),
ranked_stats AS (
    SELECT
        mwh.*,
        cma.country_avg_amount,
        RANK() OVER (PARTITION BY mwh.country_id, mwh.payment_month ORDER BY mwh.monthly_amount DESC) AS country_rank
    FROM monthly_with_history AS mwh
    JOIN country_monthly_avg AS cma ON cma.country_id = mwh.country_id AND cma.payment_month = mwh.payment_month
),
top_staff_per_month AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_sum,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) AS rn
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
)
SELECT
    rs.customer_id,
    rs.payment_month,
    rs.monthly_amount,
    rs.payment_count,
    rs.avg_check,
    rs.distinct_payment_days,
    rs.country_name,
    rs.city_name,
    rs.store_id,
    rs.country_rank,
    ts.staff_id AS top_staff_id,
    s.o02 || ' ' || s.o03 AS top_staff_name
FROM ranked_stats AS rs
JOIN top_staff_per_month AS ts ON ts.customer_id = rs.customer_id AND ts.payment_month = rs.payment_month AND ts.rn = 1
JOIN stf AS s ON s.o01 = ts.staff_id
WHERE (rs.prev_month_amount > 0 AND rs.monthly_amount >= 3 * rs.prev_month_amount)
   OR (rs.monthly_amount > 2 * rs.country_avg_amount)
ORDER BY rs.payment_month DESC, rs.monthly_amount DESC;