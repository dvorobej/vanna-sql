WITH
payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS month_payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_monthly_stats AS (
  SELECT
    pm.*,
    AVG(pm.month_amount) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount,
    COUNT(*) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_cnt
  FROM payment_monthly AS pm
),
customer_monthly_filtered AS (
  SELECT
    cms.*,
    (cms.month_amount - cms.prev_avg_month_amount) AS deviation_from_prev_avg
  FROM customer_monthly_stats AS cms
  WHERE cms.month_start >= '2005-01-01'
    AND cms.month_start < '2006-01-01'
    AND cms.prev_months_cnt > 0
    AND cms.month_amount >= 2.0 * cms.prev_avg_month_amount
    AND cms.month_payment_count >= 5
),
staff_store_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT sf.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS sf
    ON sf.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
per_month_ok AS (
  SELECT
    cmf.customer_id,
    cmf.month_start,
    cmf.month_amount,
    cmf.month_payment_count,
    cmf.prev_avg_month_amount,
    cmf.deviation_from_prev_avg,
    COALESCE(ssm.distinct_staff_count, 0) AS distinct_staff_count,
    COALESCE(ssm.distinct_store_count, 0) AS distinct_store_count
  FROM customer_monthly_filtered AS cmf
  JOIN staff_store_monthly AS ssm
    ON ssm.customer_id = cmf.customer_id
   AND ssm.month_start = cmf.month_start
  WHERE ssm.distinct_staff_count >= 2
     OR ssm.distinct_store_count >= 2
),
customer_all_months AS (
  SELECT
    pmo.customer_id
  FROM per_month_ok AS pmo
  GROUP BY pmo.customer_id
  HAVING COUNT(*) = 12
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
ranked AS (
  SELECT
    pmo.*,
    cg.country_name,
    cg.city_name,
    RANK() OVER (
      PARTITION BY cg.country_name, pmo.month_start
      ORDER BY pmo.month_amount DESC
    ) AS country_month_amount_rank
  FROM per_month_ok AS pmo
  JOIN customer_all_months AS cam
    ON cam.customer_id = pmo.customer_id
  JOIN customer_geo AS cg
    ON cg.customer_id = pmo.customer_id
)
SELECT
  strftime('%Y-%m', r.month_start) AS payment_month,
  r.country_name AS country,
  r.city_name AS city,
  ROUND(r.month_amount, 2) AS month_amount,
  r.month_payment_count AS payment_count,
  ROUND(r.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  r.country_month_amount_rank
FROM ranked AS r
ORDER BY
  r.payment_month,
  r.country,
  r.country_month_amount_rank,
  r.customer_id;