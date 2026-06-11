WITH monthly_customer_store_staff AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    p.p03 AS staff_id,
    s.o02 AS staff_first_name,
    s.o03 AS staff_last_name,
    c.h02 AS store_id,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    date(p.p06, 'start of month') AS month_start,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    COUNT(*) AS payment_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ci.d03
  GROUP BY
    p.p02,
    c.h03,
    c.h04,
    p.p03,
    s.o02,
    s.o03,
    c.h02,
    cn.c01,
    cn.c02,
    date(p.p06, 'start of month')
),
month_country_avg AS (
  SELECT
    country_id,
    month_start,
    AVG(month_amount) AS country_avg_month_amount
  FROM monthly_customer_store_staff
  GROUP BY country_id, month_start
),
ranked_by_country AS (
  SELECT
    mc.*,
    RANK() OVER (
      PARTITION BY mc.country_id
      ORDER BY mc.month_amount DESC
    ) AS rank_in_country,
    LAG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id, mc.country_id, mc.store_id, mc.staff_id
      ORDER BY mc.month_start
    ) AS prev_month_amount_same_entity,
    mca.country_avg_month_amount
  FROM monthly_customer_store_staff AS mc
  JOIN month_country_avg AS mca
    ON mca.country_id = mc.country_id
   AND mca.month_start = mc.month_start
),
top_per_month_customer_store_staff AS (
  SELECT
    *
  FROM ranked_by_country
  WHERE (month_start, country_id, store_id, staff_id) IN (
    SELECT
      month_start,
      country_id,
      store_id,
      staff_id
    FROM ranked_by_country
    GROUP BY month_start, country_id, store_id, staff_id
  )
)
SELECT
  r.country_name,
  r.city_dummy AS city_name,
  r.store_id,
  r.staff_id,
  r.staff_first_name || ' ' || r.staff_last_name AS staff_name,
  r.customer_id,
  r.first_name,
  r.last_name,
  r.month_start,
  ROUND(r.month_amount, 2) AS month_amount,
  r.payment_count,
  r.rank_in_country,
  ROUND(r.prev_month_amount_same_entity, 2) AS prev_month_amount,
  ROUND(r.month_amount - r.prev_month_amount_same_entity, 2) AS deviation_from_prev_month,
  ROUND(r.month_amount - r.country_avg_month_amount, 2) AS deviation_from_country_avg,
  ROUND(r.country_avg_month_amount, 2) AS country_avg_month_amount
FROM ranked_by_country AS r
ORDER BY
  r.country_name,
  r.month_start,
  r.rank_in_country,
  r.customer_id,
  r.store_id,
  r.staff_id;