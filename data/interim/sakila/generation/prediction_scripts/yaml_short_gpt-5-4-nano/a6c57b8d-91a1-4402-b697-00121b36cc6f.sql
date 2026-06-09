WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    city.d01 AS city_id,
    city.d02 AS city_name,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS month_payment_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = city.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
    AND p.p04 IS NOT NULL
  GROUP BY
    c.h01, c.h03, c.h04,
    cnt.c01, cnt.c02,
    city.d01, city.d02,
    date(p.p06, 'start of month')
),
personal_avg AS (
  SELECT
    customer_id,
    AVG(month_amount) AS personal_avg_amount,
    AVG(month_payment_count) AS personal_avg_payment_count
  FROM monthly_customer
  GROUP BY customer_id
),
country_avg AS (
  SELECT
    country_id,
    AVG(month_amount) AS country_avg_amount,
    AVG(month_payment_count) AS country_avg_payment_count
  FROM monthly_customer
  GROUP BY country_id
),
monthly_enriched AS (
  SELECT
    mc.*,
    pa.personal_avg_amount,
    pa.personal_avg_payment_count,
    ca.country_avg_amount,
    ca.country_avg_payment_count,
    (mc.month_amount - pa.personal_avg_amount) AS deviation_from_personal_amount,
    (mc.month_payment_count - pa.personal_avg_payment_count) AS deviation_from_personal_count,
    (mc.month_amount - ca.country_avg_amount) AS deviation_from_country_amount,
    (mc.month_payment_count - ca.country_avg_payment_count) AS deviation_from_country_count
  FROM monthly_customer AS mc
  JOIN personal_avg AS pa
    ON pa.customer_id = mc.customer_id
  JOIN country_avg AS ca
    ON ca.country_id = mc.country_id
),
top_staff_per_customer_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
    AND p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  QUALIFY 1=1
),
staff_ranked AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, COUNT(*) DESC, p.p03
    ) AS rn
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
    AND p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
)
SELECT
  me.customer_id,
  me.first_name,
  me.last_name,
  me.country_name AS country,
  me.city_name AS city,
  strftime('%Y-%m', me.month_start) AS month,
  ROUND(me.month_amount, 2) AS month_amount,
  me.month_payment_count,
  ROUND(me.deviation_from_personal_amount, 2) AS deviation_from_personal_amount,
  ROUND(me.deviation_from_personal_count, 2) AS deviation_from_personal_count,
  ROUND(me.deviation_from_country_amount, 2) AS deviation_from_country_amount,
  ROUND(me.deviation_from_country_count, 2) AS deviation_from_country_count,
  RANK() OVER (
    PARTITION BY me.country_id, me.month_start
    ORDER BY me.month_amount DESC
  ) AS amount_rank_in_country_month,
  st.o01 AS staff_id,
  st.o02 || ' ' || st.o03 AS staff_name
FROM monthly_enriched AS me
LEFT JOIN staff_ranked AS sr
  ON sr.customer_id = me.customer_id
 AND sr.month_start = me.month_start
 AND sr.rn = 1
LEFT JOIN stf AS st
  ON st.o01 = sr.staff_id
ORDER BY
  me.country_name,
  me.month_start,
  amount_rank_in_country_month,
  me.customer_id;