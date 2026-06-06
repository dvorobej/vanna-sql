WITH payment_details AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_full_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    city.d02 AS city_name,
    strftime('%Y-%m', p.p06) AS payment_month,
    p.p05 AS amount,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    r.q01 AS rental_id,
    CASE
      WHEN r.q05 IS NOT NULL
       AND f.i07 IS NOT NULL
       AND julianday(r.q05) > julianday(r.q02) + f.i07
      THEN 1
      ELSE 0
    END AS overdue_flag
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = city.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flm AS f
    ON f.i01 = i.n02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
monthly_customer AS (
  SELECT
    customer_id,
    customer_full_name,
    country_id,
    country_name,
    city_name,
    payment_month,
    COUNT(*) AS payment_count,
    SUM(amount) AS total_amount,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT store_id) AS distinct_store_count,
    CASE
      WHEN COUNT(rental_id) > 0
      THEN SUM(overdue_flag) * 1.0 / COUNT(rental_id)
      ELSE 0
    END AS overdue_return_share
  FROM payment_details
  GROUP BY
    customer_id,
    customer_full_name,
    country_id,
    country_name,
    city_name,
    payment_month
),
country_month_avg AS (
  SELECT
    country_id,
    payment_month,
    AVG(total_amount) AS country_avg_monthly_amount
  FROM monthly_customer
  GROUP BY
    country_id,
    payment_month
),
ranked_customers AS (
  SELECT
    mc.*,
    cma.country_avg_monthly_amount,
    RANK() OVER (
      PARTITION BY mc.country_id, mc.payment_month
      ORDER BY mc.total_amount DESC
    ) AS country_payment_rank
  FROM monthly_customer AS mc
  JOIN country_month_avg AS cma
    ON cma.country_id = mc.country_id
   AND cma.payment_month = mc.payment_month
)
SELECT
  payment_month AS month,
  country_name AS country,
  city_name AS city,
  customer_id,
  customer_full_name,
  ROUND(total_amount, 2) AS total_amount,
  payment_count,
  ROUND(country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
  ROUND(overdue_return_share, 4) AS overdue_return_share,
  distinct_staff_count,
  distinct_store_count,
  country_payment_rank
FROM ranked_customers
WHERE total_amount > country_avg_monthly_amount * 1.5
  AND (
    distinct_staff_count >= 3
    OR distinct_store_count >= 3
  )
ORDER BY
  payment_month,
  country_name,
  country_payment_rank,
  total_amount DESC;