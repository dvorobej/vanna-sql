WITH
monthly_customer AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h02 AS home_store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS month_start,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_sum,
        AVG(p.p05) AS avg_check,
        COUNT(DISTINCT date(p.p06)) AS active_days
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    WHERE c.h07 = 'Y'
    GROUP BY
        p.p02, c.h03, c.h04, c.h02,
        co.c01, co.c02, strftime('%Y-%m', p.p06)
),
monthly_with_prev AS (
    SELECT
        mc.*,
        LAG(mc.monthly_sum) OVER (
            PARTITION BY mc.customer_id
            ORDER BY mc.month_start
        ) AS prev_monthly_sum,
        AVG(mc.monthly_sum) OVER (
            PARTITION BY mc.country_id, mc.month_start
        ) AS country_avg_monthly_sum
    FROM monthly_customer AS mc
),
top_staff_per_month AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month_start,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_month_sum,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, strftime('%Y-%m', p.p06)
            ORDER BY SUM(p.p05) DESC, p.p03
        ) AS rn
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
),
ranked AS (
    SELECT
        mwp.*,
        RANK() OVER (
            PARTITION BY mwp.country_id, mwp.month_start
            ORDER BY mwp.monthly_sum DESC
        ) AS customer_country_rank,
        tsp.staff_id AS top_staff_id
    FROM monthly_with_prev AS mwp
    LEFT JOIN top_staff_per_month AS tsp
        ON tsp.customer_id = mwp.customer_id
       AND tsp.month_start = mwp.month_start
       AND tsp.rn = 1
)
SELECT
    r.customer_id,
    r.first_name,
    r.last_name,
    r.country_name AS country,
    r.home_store_id AS store_id,
    r.month_start AS month,
    r.payment_count,
    ROUND(r.monthly_sum, 2) AS monthly_sum,
    ROUND(r.avg_check, 2) AS avg_check,
    r.active_days,
    r.prev_monthly_sum,
    ROUND(r.country_avg_monthly_sum, 2) AS country_avg_monthly_sum,
    r.customer_country_rank,
    r.top_staff_id AS top_staff_id,
    s.o02 || ' ' || s.o03 AS top_staff_name
FROM ranked AS r
LEFT JOIN stf AS s
    ON s.o01 = r.top_staff_id
WHERE
    (
        r.prev_monthly_sum IS NOT NULL
        AND r.monthly_sum >= 3.0 * r.prev_monthly_sum
    )
    OR (
        r.country_avg_monthly_sum IS NOT NULL
        AND r.monthly_sum > 2.0 * r.country_avg_monthly_sum
    )
ORDER BY
    r.month_start,
    r.country_name,
    r.customer_country_rank,
    r.monthly_sum DESC;