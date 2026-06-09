WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS amount,
    date(p.p06, 'start of month') AS month_start,
    -- customer geo
    cus.h02 AS customer_home_store_id,
    cnt_c.c01 AS customer_country_id,
    cnt_c.c02 AS customer_country_name,
    cty_c.d02 AS customer_city_name,
    -- film categories
    fc.l02 AS film_category_id
  FROM pay AS p
  JOIN cus AS cus
    ON cus.h01 = p.p02
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS inv
    ON inv.n01 = r.q03
  JOIN flm AS f
    ON f.i01 = inv.n02
  JOIN flc AS fc
    ON fc.l01 = f.i01
  -- customer geo via address -> city -> country
  JOIN adr AS adr_c
    ON adr_c.e01 = cus.h06
  JOIN cty AS cty_c
    ON cty_c.d01 = adr_c.e05
  JOIN cnt AS cnt_c
    ON cnt_c.c01 = cty_c.d03
  WHERE p.p06 IS NOT NULL
),
monthly_customer_base AS (
  SELECT
    customer_id,
    month_start,
    customer_country_id,
    customer_country_name,
    customer_city_name,
    customer_home_store_id,
    SUM(amount) AS month_total_amount,
    COUNT(*) AS payment_count,
    MAX(amount) AS max_payment,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    -- payments outside registration store:
    SUM(
      CASE
        WHEN (rental_store.inv_store_id IS NOT NULL AND rental_store.inv_store_id <> customer_home_store_id) THEN 1
        ELSE 0
      END
    ) AS payments_outside_home_store_count,
    COUNT(*) AS payments_total_for_share,
    COUNT(DISTINCT film_category_id) AS distinct_film_category_count
  FROM (
    SELECT
      pe.*,
      -- store id where rental inventory belongs
      i.n03 AS inv_store_id
    FROM payment_enriched pe
    JOIN ren r2 ON r2.q01 = pe.rental_id
    JOIN inv i ON i.n01 = r2.q03
  ) AS rental_store
  GROUP BY
    customer_id,
    month_start,
    customer_country_id,
    customer_country_name,
    customer_city_name,
    customer_home_store_id
),
monthly_customer_scored AS (
  SELECT
    mcb.*,
    AVG(month_total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_amount
  FROM monthly_customer_base AS mcb
)
SELECT
  month_start AS month,
  customer_country_name AS country,
  customer_city_name AS city,
  ROUND(month_total_amount, 2) AS month_payment_sum,
  payment_count,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(
    1.0 * payments_outside_home_store_count / NULLIF(payments_total_for_share, 0),
    4
  ) AS outside_home_store_payment_share,
  RANK() OVER (
    PARTITION BY customer_country_id, month_start
    ORDER BY month_total_amount DESC
  ) AS country_month_rank
FROM monthly_customer_scored
WHERE
  avg_prev_3_months_amount IS NOT NULL
  AND avg_prev_3_months_amount > 0
  AND month_total_amount > avg_prev_3_months_amount * 3.0
  AND distinct_staff_count >= 2
  AND distinct_film_category_count >= 3
ORDER BY
  country,
  month,
  month_payment_sum DESC,
  customer_id;