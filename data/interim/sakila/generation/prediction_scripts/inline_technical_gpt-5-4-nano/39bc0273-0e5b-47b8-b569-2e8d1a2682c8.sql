WITH base AS (
    SELECT
        c.h01 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        c.h02 AS customer_store_id,
        ct.d03 AS country_id
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN stf AS s
        ON s.o01 = p.p03
),
monthly AS (
    SELECT
        customer_id,
        month_start,
        country_id,
        COUNT(*) AS payment_count,
        SUM(amount) AS monthly_sum,
        AVG(amount) AS avg_check,
        COUNT(DISTINCT date(p06_start.payment_day)) AS active_days,
        SUM(CASE WHEN staff_store_id = customer_store_id THEN 1 ELSE 0 END) AS same_store_payment_count
    FROM (
        SELECT
            customer_id,
            month_start,
            country_id,
            amount,
            staff_store_id,
            payment_day
        FROM (
            SELECT
                b.customer_id,
                b.month_start,
                b.country_id,
                b.amount,
                b.staff_store_id,
                date(b.month_start, '+0 days') AS payment_day
            FROM (
                SELECT
                    c.h01 AS customer_id,
                    date(p.p06, 'start of month') AS month_start,
                    p.p05 AS amount,
                    p.p03 AS staff_id,
                    s.o07 AS staff_store_id,
                    c.h02 AS customer_store_id,
                    ct.d03 AS country_id,
                    date(p.p06) AS payment_day
                FROM pay AS p
                JOIN cus AS c
                    ON c.h01 = p.p02
                JOIN adr AS a
                    ON a.e01 = c.h06
                JOIN cty AS ct
                    ON ct.d01 = a.e05
                JOIN stf AS s
                    ON s.o01 = p.p03
            ) AS b
        ) AS x
    ) AS p06_start
    GROUP BY customer_id, month_start, country_id
),
monthly_calc AS (
    SELECT
        m.*,
        LAG(m.monthly_sum) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
        ) AS prev_monthly_sum,
        AVG(m.monthly_sum) OVER (
            PARTITION BY country_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS country_avg_monthly_sum
    FROM monthly AS m
),
country_month_avg AS (
    SELECT
        country_id,
        month_start,
        AVG(monthly_sum) AS country_avg_monthly_sum
    FROM monthly_calc
    GROUP BY country_id, month_start
),
ranked AS (
    SELECT
        mc.customer_id,
        mc.month_start,
        mc.country_id,
        mc.payment_count,
        mc.monthly_sum,
        mc.avg_check,
        mc.active_days,
        mc.prev_monthly_sum,
        cma.country_avg_monthly_sum,
        RANK() OVER (
            PARTITION BY mc.country_id, mc.month_start
            ORDER BY mc.monthly_sum DESC
        ) AS country_month_payment_rank,
        CASE
            WHEN mc.prev_monthly_sum IS NOT NULL AND mc.prev_monthly_sum > 0
                THEN mc.monthly_sum / mc.prev_monthly_sum
            ELSE NULL
        END AS ratio_to_prev_month,
        CASE
            WHEN cma.country_avg_monthly_sum IS NOT NULL AND cma.country_avg_monthly_sum > 0
                THEN mc.monthly_sum / cma.country_avg_monthly_sum
            ELSE NULL
        END AS ratio_to_country_avg
    FROM monthly_calc mc
    JOIN country_month_avg cma
      ON cma.country_id = mc.country_id
     AND cma.month_start = mc.month_start
),
top_staff_month AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_month_sum,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, date(p.p06, 'start of month')
            ORDER BY SUM(p.p05) DESC, p.p03
        ) AS rn
    FROM pay AS p
    WHERE p.p06 IS NOT NULL
    GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
)
SELECT
    r.customer_id AS h01,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    cn.c02 AS country,
    ci.d02 AS city,
    c.h02 AS customer_store_id_j01,
    r.month_start AS month,
    ROUND(r.monthly_sum, 2) AS monthly_payment_sum,
    r.payment_count,
    ROUND(r.avg_check, 2) AS avg_check,
    r.active_days,
    ROUND(r.prev_monthly_sum, 2) AS prev_monthly_sum,
    ROUND(r.country_avg_monthly_sum, 2) AS country_avg_monthly_sum,
    r.country_month_payment_rank,
    st.o01 AS top_staff_id,
    st.o02 AS top_staff_first_name,
    st.o03 AS top_staff_last_name,
    ts.staff_month_sum AS top_staff_payment_sum,
    ssto.j01 AS staff_store_id
FROM ranked r
JOIN cus c
  ON c.h01 = r.customer_id
JOIN adr a
  ON a.e01 = c.h06
JOIN cty ci
  ON ci.d01 = a.e05
JOIN cnt cn
  ON cn.c01 = ci.d03
LEFT JOIN top_staff_month ts
  ON ts.customer_id = r.customer_id
 AND ts.month_start = r.month_start
 AND ts.rn = 1
LEFT JOIN stf st
  ON st.o01 = ts.staff_id
LEFT JOIN sto ssto
  ON ssto.j01 = st.o07
WHERE
    (
      r.prev_monthly_sum IS NOT NULL
      AND r.prev_monthly_sum > 0
      AND r.monthly_sum >= 3.0 * r.prev_monthly_sum
    )
    OR (
      r.country_avg_monthly_sum IS NOT NULL
      AND r.country_avg_monthly_sum > 0
      AND r.monthly_sum >= 2.0 * r.country_avg_monthly_sum
    )
ORDER BY
    r.month_start,
    cn.c02,
    r.country_month_payment_rank,
    r.monthly_sum DESC,
    r.customer_id;