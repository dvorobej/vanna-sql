WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    cu.h02 AS home_store_id
  FROM pay AS p
  JOIN cus AS cu
    ON cu.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
monthly_customer AS (
  SELECT
    py.customer_id,
    py.month_start,
    SUM(py.payment_amount) AS month_amount,
    COUNT(py.payment_id) AS payment_count
  FROM payments_2005 AS py
  GROUP BY
    py.customer_id,
    py.month_start
),
customer_country AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
customer_month_stats AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
    ) AS personal_avg_month_amount
  FROM monthly_customer AS mc
),
country_month_ranked AS (
  SELECT
    cms.*,
    RANK() OVER (
      PARTITION BY cms.country_name, cms.month_start
      ORDER BY cms.month_amount DESC
    ) AS country_month_amount_rank,
    COUNT(*) OVER (
      PARTITION BY cms.country_name, cms.month_start
    ) AS country_month_customer_count
  FROM customer_month_stats AS cms
  JOIN customer_country AS cc
    ON cc.customer_id = cms.customer_id
),
top_10pct_country_month AS (
  SELECT
    *,
    (country_month_customer_count * 0.10) AS top10pct_exact_count,
    CAST((country_month_customer_count * 0.10) AS INTEGER) AS top10pct_floor_count
  FROM country_month_ranked
),
top_staff_in_month AS (
  SELECT
    py.customer_id,
    py.month_start,
    py.staff_id,
    SUM(py.payment_amount) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY py.customer_id, py.month_start
      ORDER BY SUM(py.payment_amount) DESC, py.staff_id
    ) AS rn
  FROM payments_2005 AS py
  GROUP BY
    py.customer_id,
    py.month_start,
    py.staff_id
)
SELECT
  t.customer_id,
  cc.country_name,
  cc.city_name,
  strftime('%Y-%m', t.month_start) AS month,
  ROUND(t.month_amount, 2) AS month_amount,
  t.payment_count,
  ROUND(t.month_amount - t.personal_avg_month_amount, 2) AS deviation_from_personal_avg,
  RANK() OVER (
    PARTITION BY cc.country_name, t.month_start
    ORDER BY t.month_amount DESC
  ) AS customer_rank_in_country,
  stf.o01 AS staff_id,
  stf.o02 || ' ' || stf.o03 AS staff_full_name
FROM top_10pct_country_month AS t
JOIN customer_country AS cc
  ON cc.customer_id = t.customer_id
JOIN top_staff_in_month AS ts
  ON ts.customer_id = t.customer_id
 AND ts.month_start = t.month_start
 AND ts.rn = 1
JOIN stf
  ON stf.o01 = ts.staff_id
WHERE t.personal_avg_month_amount > 0
  AND t.month_amount > 2.0 * t.personal_avg_month_amount
  AND (
    t.country_month_amount_rank <= CASE
      WHEN t.top10pct_exact_count = t.top10pct_floor_count
        THEN t.top10pct_floor_count
      ELSE t.top10pct_floor_count + 1
    END
  )
ORDER BY
  cc.country_name,
  t.month_start,
  t.month_amount DESC,
  t.customer_id;