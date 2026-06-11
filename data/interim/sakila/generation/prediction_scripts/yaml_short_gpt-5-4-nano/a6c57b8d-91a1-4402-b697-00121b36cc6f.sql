WITH monthly_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    ct.d02 AS city_name,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS payment_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cn.c01,
    cn.c02,
    ct.d02,
    date(p.p06, 'start of month')
),
with_avgs AS (
  SELECT
    mp.*,
    AVG(mp.month_amount) OVER (
      PARTITION BY mp.customer_id
    ) AS customer_avg_month_amount,
    AVG(mp.payment_count) OVER (
      PARTITION BY mp.customer_id
    ) AS customer_avg_month_payment_count,
    AVG(mp.month_amount) OVER (
      PARTITION BY mp.country_id
    ) AS country_avg_month_amount,
    AVG(mp.payment_count) OVER (
      PARTITION BY mp.country_id
    ) AS country_avg_month_payment_count
  FROM monthly_payments AS mp
),
suspicious AS (
  SELECT
    wa.*,
    (wa.month_amount - wa.customer_avg_month_amount) AS deviation_from_customer_avg_amount,
    (wa.payment_count - wa.customer_avg_month_payment_count) AS deviation_from_customer_avg_count
  FROM with_avgs AS wa
  WHERE
    wa.month_amount >= 2.0 * wa.customer_avg_month_amount
    OR wa.payment_count >= 2.0 * wa.customer_avg_month_payment_count
    OR wa.month_amount >= 2.0 * wa.country_avg_month_amount
    OR wa.payment_count >= 2.0 * wa.country_avg_month_payment_count
),
top_staff_by_month AS (
  SELECT
    p.p02 AS customer_id,
    cn.c01 AS country_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, cn.c01, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC
    ) AS rn
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
    AND p.p03 IS NOT NULL
  GROUP BY
    p.p02,
    cn.c01,
    date(p.p06, 'start of month'),
    p.p03
)
SELECT
  s.customer_id,
  s.first_name,
  s.last_name,
  s.country_name AS country,
  s.city_name AS city,
  strftime('%Y-%m', s.month_start) AS month,
  ROUND(s.deviation_from_customer_avg_amount, 2) AS deviation_from_customer_avg_amount,
  RANK() OVER (
    PARTITION BY s.country_id, s.month_start
    ORDER BY s.deviation_from_customer_avg_amount DESC
  ) AS country_rank_by_deviation,
  s.payment_count,
  ROUND(s.month_amount, 2) AS month_payments_sum,
  ts.staff_id AS top_staff_id
FROM suspicious AS s
LEFT JOIN top_staff_by_month AS ts
  ON ts.customer_id = s.customer_id
 AND ts.country_id = s.country_id
 AND ts.month_start = s.month_start
 AND ts.rn = 1
ORDER BY
  s.country_name,
  s.month_start,
  country_rank_by_deviation,
  s.customer_id;