WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS month_label
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    ct.c02 AS country,
    ct.c01 AS country_id,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS ct ON ct.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    p.customer_id,
    p.month_start,
    p.month_label,
    COUNT(p.payment_id) AS payment_count,
    SUM(p.payment_amount) AS monthly_amount
  FROM payments_2005 AS p
  GROUP BY
    p.customer_id,
    p.month_start,
    p.month_label
),
customer_monthly_with_avg AS (
  SELECT
    mc.*,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.customer_id
    ) AS personal_avg_monthly_amount
  FROM monthly_customer AS mc
),
customer_monthly_with_country_stats AS (
  SELECT
    cm.*,
    cg.country_id,
    cg.country,
    cg.city,
    RANK() OVER (
      PARTITION BY cg.country_id, cm.month_start
      ORDER BY cm.monthly_amount DESC
    ) AS country_month_rank
  FROM customer_monthly_with_avg AS cm
  JOIN customer_geo AS cg
    ON cg.customer_id = cm.customer_id
),
country_month_top10 AS (
  SELECT
    country_id,
    month_start,
    COUNT(*) AS customers_in_country_month
  FROM customer_monthly_with_country_stats
  GROUP BY country_id, month_start
),
flagged_months AS (
  SELECT
    cms.*,
    (cms.monthly_amount - cms.personal_avg_monthly_amount) AS deviation_from_avg_amount,
    (cms.monthly_amount / NULLIF(cms.personal_avg_monthly_amount, 0)) AS ratio_to_personal_avg,
    CASE
      WHEN cms.monthly_amount >= 2.0 * cms.personal_avg_monthly_amount THEN 1
      ELSE 0
    END AS meets_personal_threshold,
    CASE
      WHEN cms.country_month_rank
           <= CAST( (cmt10.customers_in_country_month * 0.10) AS INTEGER )
           OR cms.country_month_rank = 1
      THEN 1 ELSE 0
    END AS in_top10_country
  FROM customer_monthly_with_country_stats AS cms
  JOIN country_month_top10 AS cmt10
    ON cmt10.country_id = cms.country_id
   AND cmt10.month_start = cms.month_start
  WHERE cms.personal_avg_monthly_amount IS NOT NULL
),
month_top_staff AS (
  SELECT
    p.customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.staff_id
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
  f.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  f.country,
  f.city,
  f.month_label AS month,
  ROUND(f.monthly_amount, 2) AS monthly_amount,
  f.payment_count,
  ROUND(f.deviation_from_avg_amount, 2) AS deviation_from_personal_avg,
  f.country_month_rank AS country_month_rank,
  stf.o02 AS staff_first_name,
  stf.o03 AS staff_last_name
FROM flagged_months AS f
JOIN cus AS c
  ON c.h01 = f.customer_id
JOIN month_top_staff AS mts
  ON mts.customer_id = f.customer_id
 AND mts.month_start = f.month_start
 AND mts.rn = 1
JOIN stf AS stf
  ON stf.o01 = mts.staff_id
WHERE f.meets_personal_threshold = 1
  AND f.in_top10_country = 1
ORDER BY
  f.month_start,
  f.country,
  f.monthly_amount DESC,
  f.customer_id;