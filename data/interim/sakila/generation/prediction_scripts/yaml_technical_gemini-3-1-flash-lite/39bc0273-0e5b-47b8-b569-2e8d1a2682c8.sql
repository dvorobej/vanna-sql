WITH monthly_stats AS (
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
        ms.*,
        cg.store_id,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        LAG(ms.monthly_amount) OVER (PARTITION BY ms.customer_id ORDER BY ms.payment_month) AS prev_month_amount
    FROM monthly_stats AS ms
    JOIN customer_geo AS cg ON cg.customer_id = ms.customer_id
),
country_monthly_avg AS (
    SELECT
        country_id,
        payment_month,
        AVG(monthly_amount) AS country_avg_amount
    FROM monthly_with_history
    GROUP BY country_id, payment_month
),
staff_monthly_top AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_amount,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) AS rn
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
)
SELECT
    mwh.customer_id,
    mwh.payment_month,
    mwh.monthly_amount,
    mwh.payment_count,
    mwh.avg_check,
    mwh.distinct_payment_days,
    mwh.country_name,
    mwh.city_name,
    mwh.store_id,
    smt.staff_id AS top_staff_id,
    RANK() OVER (PARTITION BY mwh.country_id, mwh.payment_month ORDER BY mwh.monthly_amount DESC) AS country_rank
FROM monthly_with_history AS mwh
JOIN country_monthly_avg AS cma 
    ON cma.country_id = mwh.country_id 
    AND cma.payment_month = mwh.payment_month
JOIN staff_monthly_top AS smt 
    ON smt.customer_id = mwh.customer_id 
    AND smt.payment_month = mwh.payment_month 
    AND smt.rn = 1
WHERE (mwh.prev_month_amount IS NOT NULL AND mwh.monthly_amount >= 3 * mwh.prev_month_amount)
   OR (mwh.monthly_amount > 2 * cma.country_avg_amount)
ORDER BY mwh.payment_month DESC, mwh.monthly_amount DESC;