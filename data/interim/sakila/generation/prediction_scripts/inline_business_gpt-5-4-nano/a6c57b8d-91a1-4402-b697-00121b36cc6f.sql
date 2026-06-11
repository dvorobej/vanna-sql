WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    c.h02 AS home_store_id,
    cu_city.city_id,
    cu_city.city_name,
    cu_city.country_id,
    cu_city.country_name,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN (
    SELECT
      a.e01 AS address_id,
      ct.d03 AS country_id,
      cn.c02 AS country_name,
      a2.d01 AS city_id,
      a2.d02 AS city_name
    FROM adr AS a
    JOIN city AS a2
      ON a2.e01 = a.e01
    JOIN cty AS ct
      ON ct.d01 = a.e05
    JOIN cnt AS cn
      ON cn.c01 = ct.d03
  ) AS cu_city
    ON cu_city.address_id = c.h06
),
monthly_customer AS (
  SELECT
    customer_id,
    customer_name,
    country_id,
    country_name,
    city_id,
    city_name,
    month_start,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_amount
  FROM payment_enriched
  WHERE month_start >= '2005-01-01' AND month_start < '2006-01-01'
  GROUP BY
    customer_id, customer_name, country_id, country_name, city_id, city_name, month_start
),
monthly_with_personal_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_personal_avg_month_amount
  FROM monthly_customer mc
),
monthly_country_rank AS (
  SELECT
    mpa.*,
    PERCENT_RANK() OVER (
      PARTITION BY mpa.country_id, mpa.month_start
      ORDER BY mpa.month_amount DESC
    ) AS country_percent_rank
  FROM monthly_with_personal_avg mpa
),
top_staff_per_month AS (
  SELECT
    p.customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, date(p.p06, 'start of month')
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.staff_id
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.customer_id,
    date(p.p06, 'start of month'),
    p.staff_id
),
top_staff AS (
  SELECT
    customer_id,
    month_start,
    staff_id
  FROM top_staff_per_month
  WHERE rn = 1
)
SELECT
  m.country_name,
  m.city_name,
  m.customer_id,
  m.customer_name,
  strftime('%Y-%m', m.month_start) AS activity_month,
  ROUND(m.month_amount, 2) AS month_amount,
  m.payment_count,
  ROUND(m.prev_personal_avg_month_amount, 2) AS prev_personal_avg_month_amount,
  ROUND(m.month_amount / NULLIF(m.prev_personal_avg_month_amount, 0), 2) AS amount_vs_personal_avg_ratio,
  RANK() OVER (
    PARTITION BY m.country_id, m.month_start
    ORDER BY m.month_amount DESC
  ) AS country_month_amount_rank,
  ts.staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name
FROM monthly_country_rank m
JOIN top_staff ts
  ON ts.customer_id = m.customer_id
 AND ts.month_start = m.month_start
JOIN stf s
  ON s.o01 = ts.staff_id
WHERE
  m.prev_personal_avg_month_amount IS NOT NULL
  AND m.prev_personal_avg_month_amount > 0
  AND m.month_amount > 2 * m.prev_personal_avg_month_amount
  AND m.country_percent_rank <= 0.10
ORDER BY
  m.country_name,
  m.month_start,
  m.month_amount DESC,
  m.customer_id;