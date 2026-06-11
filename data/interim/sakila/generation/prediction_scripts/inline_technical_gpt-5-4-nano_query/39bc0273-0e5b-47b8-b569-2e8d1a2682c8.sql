WITH monthly AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS customer_home_store_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        c.h06 AS customer_address_id,
        cn.c02 AS country_name,
        date(p.p06, 'start of month') AS month_start,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        COUNT(p.p01) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS monthly_sum,
        AVG(CAST(p.p05 AS REAL)) AS avg_check
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        c.h02,
        c.h03,
        c.h04,
        cn.c02,
        date(p.p06, 'start of month'),
        p.p03,
        s.o07
),
monthly_agg AS (
    SELECT
        m.customer_id,
        m.customer_home_store_id,
        m.customer_first_name,
        m.customer_last_name,
        m.country_name,
        m.month_start,
        SUM(m.payment_count) AS payment_count,
        SUM(m.monthly_sum) AS monthly_sum,
        AVG(m.avg_check) AS avg_check,
        (
            SELECT COUNT(DISTINCT date(p2.p06))
            FROM pay AS p2
            WHERE p2.p02 = m.customer_id
              AND date(p2.p06, 'start of month') = m.month_start
        ) AS active_payment_days
    FROM monthly AS m
    GROUP BY
        m.customer_id,
        m.customer_home_store_id,
        m.customer_first_name,
        m.customer_last_name,
        m.country_name,
        m.month_start
),
with_prev AS (
    SELECT
        ma.*,
        LAG(ma.monthly_sum) OVER (
            PARTITION BY ma.customer_id
            ORDER BY ma.month_start
        ) AS prev_monthly_sum
    FROM monthly_agg AS ma
),
country_avg AS (
    SELECT
        wp.month_start,
        wp.country_name,
        AVG(wp.monthly_sum) AS country_avg_monthly_sum
    FROM with_prev AS wp
    GROUP BY
        wp.month_start,
        wp.country_name
),
ranked_staff AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p03 AS staff_id,
        SUM(CAST(p.p05 AS REAL)) AS staff_month_sum,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, date(p.p06, 'start of month')
            ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
        ) AS rn
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06, 'start of month'),
        p.p03
),
max_staff AS (
    SELECT
        rs.customer_id,
        rs.month_start,
        rs.staff_id,
        rs.staff_month_sum
    FROM ranked_staff AS rs
    WHERE rs.rn = 1
)
SELECT
    wp.customer_id,
    wp.customer_first_name,
    wp.customer_last_name,
    wp.country_name,
    wp.month_start,
    wp.payment_count,
    ROUND(wp.monthly_sum, 2) AS monthly_sum,
    ROUND(wp.avg_check, 2) AS avg_check,
    wp.active_payment_days,
    wp.prev_monthly_sum,
    ROUND(
        CASE
            WHEN wp.prev_monthly_sum IS NULL OR wp.prev_monthly_sum = 0 THEN NULL
            ELSE wp.monthly_sum / wp.prev_monthly_sum
        END,
        3
    ) AS ratio_to_prev_month,
    ROUND(
        CASE
            WHEN ca.country_avg_monthly_sum IS NULL OR ca.country_avg_monthly_sum = 0 THEN NULL
            ELSE wp.monthly_sum / ca.country_avg_monthly_sum
        END,
        3
    ) AS ratio_to_country_avg,
    RANK() OVER (
        PARTITION BY wp.country_name, wp.month_start
        ORDER BY wp.monthly_sum DESC
    ) AS country_month_rank,
    wp.customer_home_store_id AS customer_store_id,
    ms.staff_id AS top_staff_id,
    (st.o02 || ' ' || st.o03) AS top_staff_name,
    st.o07 AS top_staff_store_id,
    ROUND(ms.staff_month_sum, 2) AS top_staff_month_sum
FROM with_prev AS wp
JOIN country_avg AS ca
    ON ca.month_start = wp.month_start
   AND ca.country_name = wp.country_name
LEFT JOIN max_staff AS ms
    ON ms.customer_id = wp.customer_id
   AND ms.month_start = wp.month_start
LEFT JOIN stf AS st
    ON st.o01 = ms.staff_id
WHERE
    (
        wp.prev_monthly_sum IS NOT NULL
        AND wp.prev_monthly_sum > 0
        AND wp.monthly_sum >= 3.0 * wp.prev_monthly_sum
    )
    OR (
        ca.country_avg_monthly_sum IS NOT NULL
        AND ca.country_avg_monthly_sum > 0
        AND wp.monthly_sum > 2.0 * ca.country_avg_monthly_sum
    )
ORDER BY
    wp.month_start,
    wp.country_name,
    country_month_rank,
    wp.customer_id;