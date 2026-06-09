WITH payment_details AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS amount,
    date(p.p06, 'start of month') AS month_start,
    p.p06 AS payment_date,
    c.h02 AS home_store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    st.o07 AS staff_store_id,
    flc.l02 AS film_category_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
  JOIN stf AS st
    ON st.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flm AS f
    ON f.i01 = i.n02
  LEFT JOIN flc
    ON flc.l01 = f.i01
),
monthly_base AS (
  SELECT
    customer_id,
    month_start,
    country_id,
    country_name,
    city_id,
    city_name,
    SUM(amount) AS month_total_amount,
    COUNT(*) AS payment_count,
    MAX(amount) AS max_payment,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    SUM(CASE WHEN staff_store_id <> home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS outside_home_store_payment_share,
    COUNT(DISTINCT film_category_id) AS distinct_categories_count
  FROM payment_details
  WHERE payment_id IS NOT NULL
    AND home_store_id IS NOT NULL
  GROUP BY
    customer_id,
    month_start,
    country_id,
    country_name,
    city_id,
    city_name
),
monthly_with_prev AS (
  SELECT
    mb.*,
    AVG(month_total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_amount
  FROM monthly_base AS mb
),
ranked AS (
  SELECT
    mwp.*,
    RANK() OVER (
      PARTITION BY mwp.country_id, mwp.month_start
      ORDER BY mwp.month_total_amount DESC
    ) AS country_month_rank
  FROM monthly_with_prev AS mwp
)
SELECT
  strftime('%Y-%m', month_start) AS month,
  country_name AS country,
  city_name AS city,
  ROUND(month_total_amount, 2) AS payment_sum,
  payment_count,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(outside_home_store_payment_share, 4) AS outside_home_store_payment_share,
  country_month_rank
FROM ranked
WHERE avg_prev_3_months_amount IS NOT NULL
  AND month_total_amount > 3.0 * avg_prev_3_months_amount
  AND distinct_staff_count >= 2
  AND distinct_categories_count >= 3
ORDER BY
  month,
  country,
  country_month_rank,
  payment_sum DESC;