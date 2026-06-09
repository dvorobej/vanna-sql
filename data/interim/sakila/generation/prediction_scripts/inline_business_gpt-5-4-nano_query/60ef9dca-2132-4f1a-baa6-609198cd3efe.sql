WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_ts,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ci.d02 AS city_name,
    co.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    p.customer_id,
    cg.store_id,
    cg.city_name,
    cg.country_name,
    p.month_start,
    COUNT(p.payment_id) AS payment_count,
    SUM(p.payment_amount) AS month_total_amount
  FROM payments_2005 AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.customer_id
  GROUP BY
    p.customer_id, cg.store_id, cg.city_name, cg.country_name, p.month_start
),
personal_year_avg AS (
  SELECT
    customer_id,
    AVG(month_total_amount) AS personal_avg_month_amount
  FROM monthly_customer
  GROUP BY customer_id
),
monthly_scored AS (
  SELECT
    mc.*,
    pa.personal_avg_month_amount,
    (mc.month_total_amount - pa.personal_avg_month_amount) AS deviation_from_personal_avg,
    ROW_NUMBER() OVER (
      PARTITION BY mc.store_id, mc.month_start
      ORDER BY mc.month_total_amount DESC
    ) AS store_month_rn,
    COUNT(*) OVER (
      PARTITION BY mc.store_id, mc.month_start
    ) AS store_month_customer_count
  FROM monthly_customer AS mc
  JOIN personal_year_avg AS pa
    ON pa.customer_id = mc.customer_id
),
top5pct_month AS (
  SELECT
    ms.*,
    CASE
      WHEN ms.store_month_customer_count = 0 THEN 0
      ELSE 1
    END AS dummy
  FROM monthly_scored AS ms
  WHERE
    ms.store_month_rn <= (CAST(ms.store_month_customer_count AS REAL) * 0.05)
      AND ms.personal_avg_month_amount > 0
      AND ms.month_total_amount > ms.personal_avg_month_amount * 2
),
qualified_customers AS (
  SELECT
    customer_id
  FROM top5pct_month
  GROUP BY customer_id
  HAVING COUNT(DISTINCT month_start) = 12
)
, last_staff_per_month AS (
  SELECT
    p.customer_id,
    date(p.payment_ts, 'start of month') AS month_start,
    p.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, date(p.payment_ts, 'start of month')
      ORDER BY p.payment_ts DESC, p.payment_id DESC
    ) AS rn
  FROM payments_2005 AS p
)
SELECT
  q.customer_id,
  q.store_id AS store_id,
  q.city_name,
  q.country_name,
  t.month_start AS month,
  ROUND(t.month_total_amount, 2) AS month_total_amount,
  t.payment_count,
  ROUND(t.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  t.store_month_rn AS store_month_rank,
  l.staff_id AS last_staff_id
FROM qualified_customers AS qc
JOIN top5pct_month AS t
  ON t.customer_id = qc.customer_id
JOIN (
  SELECT DISTINCT
    customer_id,
    store_id,
    city_name,
    country_name
  FROM monthly_customer
) AS q
  ON q.customer_id = t.customer_id AND q.store_id = t.store_id
JOIN last_staff_per_month AS l
  ON l.customer_id = t.customer_id
 AND l.month_start = t.month_start
 AND l.rn = 1
ORDER BY
  t.month_start,
  t.store_id,
  t.store_month_rn,
  t.customer_id;