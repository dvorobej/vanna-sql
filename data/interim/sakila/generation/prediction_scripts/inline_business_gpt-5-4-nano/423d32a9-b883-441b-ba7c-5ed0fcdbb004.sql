WITH
payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS amount,
        date(p.p06, 'start of month') AS month_start
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        co.c02 AS country,
        ct.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ct.d03
),
monthly_customer AS (
    SELECT
        p.customer_id,
        p.month_start,
        COUNT(p.payment_id) AS payment_count,
        SUM(p.amount) AS monthly_amount,
        AVG(p.amount) AS avg_check,
        COUNT(DISTINCT p.staff_id) AS distinct_staff_count
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.month_start
),
monthly_with_prev AS (
    SELECT
        mc.*,
        AVG(mc.monthly_amount) OVER (
            PARTITION BY mc.customer_id
            ORDER BY mc.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_monthly_amount
    FROM monthly_customer AS mc
),
qualified_months AS (
    SELECT
        mwp.*
    FROM monthly_with_prev AS mwp
    WHERE mwp.prev_avg_monthly_amount IS NOT NULL
      AND mwp.payment_count >= 5
      AND mwp.distinct_staff_count >= 2
      AND mwp.monthly_amount >= 2.0 * mwp.prev_avg_monthly_amount
),
ranked AS (
    SELECT
        qm.*,
        RANK() OVER (
            PARTITION BY cg.country, qm.month_start
            ORDER BY (qm.monthly_amount - qm.prev_avg_monthly_amount) DESC
        ) AS country_month_deviation_rank
    FROM qualified_months AS qm
    JOIN customer_geo AS cg
      ON cg.customer_id = qm.customer_id
)
SELECT
    strftime('%Y-%m', r.month_start) AS payment_month,
    r.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.country,
    cg.city,
    ROUND(r.monthly_amount, 2) AS monthly_amount,
    r.payment_count,
    ROUND(r.prev_avg_monthly_amount, 2) AS prev_avg_monthly_amount,
    ROUND(r.monthly_amount - r.prev_avg_monthly_amount, 2) AS deviation_amount,
    ROUND(
        CASE WHEN r.prev_avg_monthly_amount <> 0
             THEN (r.monthly_amount / r.prev_avg_monthly_amount)
             END,
        3
    ) AS deviation_ratio,
    r.country_month_deviation_rank
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
    r.month_start,
    cg.country,
    r.country_month_deviation_rank,
    r.customer_id;