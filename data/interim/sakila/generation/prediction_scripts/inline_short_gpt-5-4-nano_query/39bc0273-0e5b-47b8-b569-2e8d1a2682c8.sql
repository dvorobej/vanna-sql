WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS monthly_sum,
    AVG(p.p05) AS avg_check,
    COUNT(DISTINCT date(p.p06)) AS distinct_days_with_payments
  FROM pay p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    c.h02 AS home_store_id
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
),
monthly_with_prev AS (
  SELECT
    m.*,
    LAG(m.monthly_sum) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.month_start
    ) AS prev_monthly_sum
  FROM monthly m
),
country_month_avg AS (
  SELECT
    cg.country_id,
    m.month_start,
    AVG(m.monthly_sum) AS country_avg_monthly_sum,
    COUNT(*) AS customers_in_group
  FROM monthly_with_prev m
  JOIN customer_geo cg
    ON cg.customer_id = m.customer_id
  GROUP BY
    cg.country_id,
    m.month_start
),
monthly_ranked_top_staff AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
staff_best AS (
  SELECT
    mrts.customer_id,
    mrts.month_start,
    mrts.staff_id,
    sb.o02 || ' ' || sb.o03 AS top_staff_name,
    mrts.staff_month_sum AS top_staff_month_sum
  FROM monthly_ranked_top_staff mrts
  JOIN stf sb ON sb.o01 = mrts.staff_id
  WHERE mrts.rn = 1
),
country_month_rank AS (
  SELECT
    cg.country_id,
    m.month_start,
    m.customer_id,
    DENSE_RANK() OVER (
      PARTITION BY cg.country_id, m.month_start
      ORDER BY m.monthly_sum DESC
    ) AS customer_country_month_rank
  FROM monthly_with_prev m
  JOIN customer_geo cg
    ON cg.customer_id = m.customer_id
),
filtered AS (
  SELECT
    mwp.customer_id,
    mwp.month_start,
    mwp.payment_count,
    mwp.monthly_sum,
    mwp.avg_check,
    mwp.distinct_days_with_payments,
    mwp.prev_monthly_sum,
    cma.country_avg_monthly_sum,
    cmr.customer_country_month_rank
  FROM monthly_with_prev mwp
  JOIN customer_geo cg
    ON cg.customer_id = mwp.customer_id
  JOIN country_month_avg cma
    ON cma.country_id = cg.country_id
   AND cma.month_start = mwp.month_start
  JOIN country_month_rank cmr
    ON cmr.country_id = cg.country_id
   AND cmr.month_start = mwp.month_start
   AND cmr.customer_id = mwp.customer_id
  WHERE
    (
      mwp.prev_monthly_sum IS NOT NULL
      AND mwp.monthly_sum >= 3.0 * mwp.prev_monthly_sum
    )
    OR
    (
      cma.country_avg_monthly_sum IS NOT NULL
      AND mwp.monthly_sum > 2.0 * cma.country_avg_monthly_sum
    )
)
SELECT
  f.customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  cg.country_name AS country,
  cg.home_store_id AS customer_home_store_id,
  f.month_start AS month,
  f.payment_count,
  ROUND(f.monthly_sum, 2) AS monthly_sum,
  ROUND(f.avg_check, 2) AS avg_check,
  f.distinct_days_with_payments AS days_with_payments,
  f.customer_country_month_rank AS customer_country_month_rank,
  bb.top_staff_name AS top_staff,
  bb.staff_id AS top_staff_id,
  ROUND(bb.top_staff_month_sum, 2) AS top_staff_month_sum
FROM filtered f
JOIN cus c ON c.h01 = f.customer_id
JOIN customer_geo cg ON cg.customer_id = f.customer_id
LEFT JOIN staff_best bb
  ON bb.customer_id = f.customer_id
 AND bb.month_start = f.month_start
ORDER BY
  f.month_start,
  cg.country_name,
  f.customer_country_month_rank,
  f.monthly_sum DESC,
  f.customer_id;