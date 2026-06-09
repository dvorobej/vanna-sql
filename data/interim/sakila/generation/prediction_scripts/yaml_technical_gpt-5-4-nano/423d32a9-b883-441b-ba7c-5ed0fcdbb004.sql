WITH
payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS monthly_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN sto AS s
    ON s.j01 = c.h02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_history AS (
  SELECT
    pm.*,
    AVG(pm.monthly_amount) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_monthly_avg_amount
  FROM payment_monthly AS pm
),
qualifying_months AS (
  SELECT
    mwh.*
  FROM monthly_with_history AS mwh
  WHERE mwh.prev_monthly_avg_amount IS NOT NULL
    AND mwh.payment_count >= 5
    AND mwh.monthly_amount >= 2.0 * mwh.prev_monthly_avg_amount
    AND (mwh.distinct_staff_count >= 2 OR mwh.distinct_store_count >= 2)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
)
SELECT
  q.customer_id AS h01,
  cg.country_name AS country,
  cg.city_name AS city,
  strftime('%Y-%m', q.month_start) AS payment_month,
  q.payment_count,
  ROUND(q.monthly_amount, 2) AS monthly_amount,
  ROUND(q.prev_monthly_avg_amount, 2) AS prev_monthly_avg_amount,
  ROUND(q.monthly_amount - q.prev_monthly_avg_amount, 2) AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY cg.country_name, q.month_start
    ORDER BY (q.monthly_amount - q.prev_monthly_avg_amount) DESC
  ) AS country_month_customer_rank
FROM qualifying_months AS q
JOIN customer_geo AS cg
  ON cg.customer_id = q.customer_id
ORDER BY
  cg.country_name,
  payment_month,
  deviation_from_prev_avg DESC,
  h01;