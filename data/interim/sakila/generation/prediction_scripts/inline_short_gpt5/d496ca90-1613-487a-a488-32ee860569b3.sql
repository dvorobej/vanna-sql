WITH payment_detail AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h05 AS email,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    DATE(p.p06) AS payment_day,
    p.p01 AS payment_id,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    COALESCE(inv.n03, stf.o07) AS store_id,
    flm.i02 AS film_title
  FROM cus AS c
  JOIN pay AS p
    ON p.p02 = c.h01
  JOIN stf
    ON stf.o01 = p.p03
  JOIN adr
    ON adr.e01 = c.h06
  JOIN cty
    ON cty.d01 = adr.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  LEFT JOIN ren
    ON ren.q01 = p.p04
  LEFT JOIN inv
    ON inv.n01 = ren.q03
  LEFT JOIN flm
    ON flm.i01 = inv.n02
  WHERE c.h07 = 'Y'
),
customer_day AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    email,
    country_id,
    country_name,
    city_name,
    payment_day,
    COUNT(payment_id) AS payment_count,
    SUM(amount) AS total_amount,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT store_id) AS distinct_store_count,
    GROUP_CONCAT(DISTINCT film_title) AS rented_film_titles
  FROM payment_detail
  GROUP BY
    customer_id,
    first_name,
    last_name,
    email,
    country_id,
    country_name,
    city_name,
    payment_day
),
scored AS (
  SELECT
    cd.*,
    (
      SELECT AVG(prev.total_amount)
      FROM customer_day AS prev
      WHERE prev.customer_id = cd.customer_id
        AND prev.payment_day >= DATE(cd.payment_day, '-30 days')
        AND prev.payment_day < cd.payment_day
    ) AS customer_prev30_avg_daily_amount,
    (
      SELECT AVG(country_prev.total_amount)
      FROM customer_day AS country_prev
      WHERE country_prev.country_id = cd.country_id
        AND country_prev.payment_day >= DATE(cd.payment_day, '-30 days')
        AND country_prev.payment_day < cd.payment_day
    ) AS country_prev30_avg_daily_amount
  FROM customer_day AS cd
)
SELECT
  customer_id,
  first_name,
  last_name,
  email,
  country_name,
  city_name,
  payment_day,
  payment_count,
  ROUND(total_amount, 2) AS total_amount,
  distinct_staff_count,
  distinct_store_count,
  ROUND(customer_prev30_avg_daily_amount, 2) AS customer_prev30_avg_daily_amount,
  ROUND(country_prev30_avg_daily_amount, 2) AS country_prev30_avg_daily_amount,
  ROUND(total_amount / NULLIF(customer_prev30_avg_daily_amount, 0), 2) AS deviation_to_customer_avg,
  ROUND(total_amount / NULLIF(country_prev30_avg_daily_amount, 0), 2) AS deviation_to_country_avg,
  rented_film_titles
FROM scored
WHERE payment_count >= 3
  AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
  AND customer_prev30_avg_daily_amount > 0
  AND country_prev30_avg_daily_amount > 0
  AND total_amount >= 3.0 * customer_prev30_avg_daily_amount
  AND total_amount >= 3.0 * country_prev30_avg_daily_amount
ORDER BY
  total_amount DESC,
  deviation_to_customer_avg DESC,
  deviation_to_country_avg DESC,
  customer_id,
  payment_day;