WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        date(p.p06, 'start of month') AS month_start
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cn.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
),
customer_monthly AS (
    SELECT
        p.customer_id,
        p.month_start,
        SUM(p.payment_amount) AS month_amount,
        COUNT(*) AS payment_count
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.month_start
),
customer_avg AS (
    SELECT
        customer_id,
        AVG(month_amount) AS avg_month_amount_2005
    FROM customer_monthly
    GROUP BY customer_id
),
country_month_ranked AS (
    SELECT
        cm.*,
        RANK() OVER (
            PARTITION BY cm.month_start, cg.country_name
            ORDER BY cm.month_amount DESC
        ) AS country_rank_in_month,
        COUNT(*) OVER (
            PARTITION BY cm.month_start, cg.country_name
        ) AS country_customer_count
    FROM customer_monthly AS cm
    JOIN customer_geo AS cg
      ON cg.customer_id = cm.customer_id
),
thresholded AS (
    SELECT
        cmr.*,
        ca.avg_month_amount_2005,
        cg.country_name,
        cg.city_name,
        (cmr.month_amount - ca.avg_month_amount_2005) / NULLIF(ca.avg_month_amount_2005, 0) AS personal_deviation_ratio
    FROM country_month_ranked AS cmr
    JOIN customer_avg AS ca
      ON ca.customer_id = cmr.customer_id
    JOIN customer_geo AS cg
      ON cg.customer_id = cmr.customer_id
),
top_staff_per_month AS (
    SELECT
        p.customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.staff_id,
        SUM(p.payment_amount) AS staff_month_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.customer_id, date(p.p06, 'start of month')
            ORDER BY SUM(p.payment_amount) DESC, p.staff_id
        ) AS rn
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
        p.customer_id,
        date(p.p06, 'start of month'),
        p.staff_id
)
SELECT
    t.customer_id,
    t.country_name,
    t.city_name,
    strftime('%Y-%m', t.month_start) AS month,
    ROUND(t.month_amount, 2) AS month_amount,
    t.payment_count,
    ROUND(t.personal_deviation_ratio, 4) AS deviation_from_personal_avg_ratio,
    t.country_rank_in_month AS country_month_rank,
    ts.staff_id AS top_staff_id,
    st.o02 || ' ' || st.o03 AS top_staff_name,
    ROUND(ts.staff_month_amount, 2) AS top_staff_month_amount
FROM thresholded AS t
JOIN top_staff_per_month AS ts
  ON ts.customer_id = t.customer_id
 AND ts.month_start = t.month_start
 AND ts.rn = 1
JOIN stf AS st
  ON st.o01 = ts.staff_id
WHERE
    t.avg_month_amount_2005 IS NOT NULL
    AND t.avg_month_amount_2005 > 0
    AND t.month_amount > 2.0 * t.avg_month_amount_2005
    AND t.country_rank_in_month <= CAST(CEIL(0.10 * t.country_customer_count) AS INTEGER)
ORDER BY
    t.month_start,
    t.country_name,
    t.country_rank_in_month,
    t.month_amount DESC,
    t.customer_id;