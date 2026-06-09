WITH payment_month_base AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    date(p.p06) AS payment_day,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    c.h02 AS home_store_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ct.c01 AS country_id,
    ct.c02 AS country_name,
    cty.d02 AS city_name,
    COALESCE(inv.n03, s.o07) AS payment_store_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = a.e05
  JOIN cnt AS ct
    ON ct.c01 = cty.d03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN sto AS s
    ON s.j01 = i.n03
  LEFT JOIN inv AS inv
    ON inv.n01 = r.q03
),
month_customer AS (
  SELECT
    customer_id,
    payment_month,
    country_name,
    city_name,
    SUM(payment_amount) AS month_total_amount,
    COUNT(*) AS payment_count,
    MAX(payment_amount) AS max_payment_amount,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    SUM(CASE WHEN payment_store_id <> home_store_id THEN 1 ELSE 0 END) AS non_home_store_payment_count,
    CAST(SUM(CASE WHEN payment_store_id <> home_store_id THEN 1 ELSE 0 END) AS REAL)
      / NULLIF(COUNT(*), 0) AS non_home_store_payment_share
  FROM payment_month_base
  GROUP BY
    customer_id,
    payment_month,
    country_name,
    city_name
),
month_with_prev_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.payment_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3_months_avg_amount
  FROM month_customer AS mc
),
month_with_prev_avg_qual AS (
  SELECT *
  FROM month_with_prev_avg
  WHERE prev_3_months_avg_amount IS NOT NULL
    AND prev_3_months_avg_amount > 0
    AND month_total_amount > 3.0 * prev_3_months_avg_amount
    AND distinct_staff_count >= 2
),
month_category_counts AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(DISTINCT fc.l02) AS distinct_categories_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
qualified AS (
  SELECT
    m.*,
    mcat.distinct_categories_count
  FROM month_with_prev_avg_qual AS m
  JOIN month_category_counts AS mcat
    ON mcat.customer_id = m.customer_id
   AND mcat.payment_month = m.payment_month
  WHERE mcat.distinct_categories_count >= 3
),
ranked AS (
  SELECT
    q.*,
    RANK() OVER (
      PARTITION BY q.country_name, q.payment_month
      ORDER BY q.month_total_amount DESC
    ) AS country_month_amount_rank
  FROM qualified AS q
)
SELECT
  payment_month AS month,
  country_name AS country,
  city_name AS city,
  customer_id,
  ROUND(month_total_amount, 2) AS payment_sum,
  payment_count AS payment_count,
  ROUND(max_payment_amount, 2) AS max_payment,
  ROUND(non_home_store_payment_share, 4) AS non_home_store_payment_share,
  country_month_amount_rank
FROM ranked
ORDER BY
  month,
  country,
  country_month_amount_rank,
  customer_id;