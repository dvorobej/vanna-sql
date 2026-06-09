WITH monthly AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS customer_store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        sMonth.month_start AS month_start,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS payment_sum,
        AVG(p.p05) AS avg_check,
        COUNT(DISTINCT date(p.p06)) AS active_days_count
    FROM pay p
    JOIN cus c
        ON c.h01 = p.p02
    JOIN adr a
        ON a.e01 = c.h06
    JOIN cty ci
        ON ci.d01 = a.e05
    JOIN cnt co
        ON co.c01 = ci.d03
    JOIN (
        SELECT DISTINCT strftime('%Y-%m-01', p2.p06) AS month_start
        FROM pay p2
    ) sMonth
        ON sMonth.month_start = strftime('%Y-%m-01', p.p06)
    GROUP BY
        c.h01, c.h03, c.h04,
        c.h02,
        co.c01, co.c02,
        sMonth.month_start
),
monthly_with_history AS (
    SELECT
        m.*,
        LAG(m.payment_sum) OVER (
            PARTITION BY m.customer_id
            ORDER BY m.month_start
        ) AS prev_month_payment_sum,
        AVG(m.payment_sum) OVER (
            PARTITION BY m.country_id, m.month_start
        ) AS country_avg_month_payment_sum
    FROM monthly m
),
country_rank AS (
    SELECT
        mwh.*,
        RANK() OVER (
            PARTITION BY mwh.country_id, mwh.month_start
            ORDER BY mwh.payment_sum DESC
        ) AS country_month_payment_rank
    FROM monthly_with_history mwh
),
top_staff_per_month AS (
    SELECT
        c.h01 AS customer_id,
        co.c01 AS country_id,
        c.h02 AS customer_store_id,
        strftime('%Y-%m-01', p.p06) AS month_start,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_payment_sum,
        ROW_NUMBER() OVER (
            PARTITION BY c.h01, co.c01, strftime('%Y-%m-01', p.p06)
            ORDER BY SUM(p.p05) DESC, p.p03
        ) AS rn
    FROM pay p
    JOIN cus c
        ON c.h01 = p.p02
    JOIN adr a
        ON a.e01 = c.h06
    JOIN cty ci
        ON ci.d01 = a.e05
    JOIN cnt co
        ON co.c01 = ci.d03
    GROUP BY
        c.h01, co.c01, c.h02, strftime('%Y-%m-01', p.p06), p.p03
),
top_staff_filtered AS (
    SELECT
        tsm.customer_id,
        tsm.country_id,
        tsm.customer_store_id,
        tsm.month_start,
        tsm.staff_id,
        tsm.staff_payment_sum
    FROM top_staff_per_month tsm
    WHERE tsm.rn = 1
)
SELECT
    cr.customer_id,
    cr.customer_name,
    cr.country_name AS country,
    cr.customer_store_id AS store_id,
    cr.month_start AS month,
    cr.payment_count,
    ROUND(cr.payment_sum, 2) AS payment_sum,
    ROUND(cr.avg_check, 2) AS avg_check,
    cr.active_days_count AS active_days_count,
    cr.prev_month_payment_sum,
    CASE
        WHEN cr.prev_month_payment_sum IS NULL OR cr.prev_month_payment_sum = 0 THEN NULL
        ELSE ROUND(cr.payment_sum * 1.0 / cr.prev_month_payment_sum, 4)
    END AS month_over_prev_ratio,
    ROUND(cr.country_avg_month_payment_sum, 2) AS country_avg_month_payment_sum,
    CASE
        WHEN cr.country_avg_month_payment_sum IS NULL OR cr.country_avg_month_payment_sum = 0 THEN NULL
        ELSE ROUND(cr.payment_sum * 1.0 / cr.country_avg_month_payment_sum, 4)
    END AS month_over_country_avg_ratio,
    cr.country_month_payment_rank AS country_month_payment_rank,
    tsf.staff_id,
    stf.o02 || ' ' || stf.o03 AS staff_name,
    tsf.staff_payment_sum AS top_staff_payment_sum
FROM country_rank cr
JOIN top_staff_filtered tsf
    ON tsf.customer_id = cr.customer_id
   AND tsf.country_id = cr.country_id
   AND tsf.customer_store_id = cr.customer_store_id
   AND tsf.month_start = cr.month_start
JOIN stf
    ON stf.o01 = tsf.staff_id
WHERE
    (
        cr.prev_month_payment_sum IS NOT NULL
        AND cr.prev_month_payment_sum > 0
        AND cr.payment_sum >= 3.0 * cr.prev_month_payment_sum
    )
    OR (
        cr.country_avg_month_payment_sum IS NOT NULL
        AND cr.country_avg_month_payment_sum > 0
        AND cr.payment_sum > 2.0 * cr.country_avg_month_payment_sum
    )
ORDER BY
    cr.country_name,
    cr.month_start,
    cr.country_month_payment_rank,
    cr.payment_sum DESC,
    cr.customer_id;