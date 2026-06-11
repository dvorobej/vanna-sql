WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    date(p.p06) AS payment_day,
    c.h02 AS customer_store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    i.n03 AS film_store_id,
    CASE WHEN stf.o07 IS NOT NULL THEN 1 ELSE 1 END AS dummy
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
  JOIN stf AS stf
    ON stf.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
),
film_category_payments AS (
  SELECT
    pb.payment_id,
    fc.l02 AS category_id
  FROM payment_base AS pb
  JOIN ren AS r
    ON r.q01 = pb.rental_id
  JOIN inv AS inv
    ON inv.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = inv.n01
),
monthly_customer_metrics AS (
  SELECT
    pb.customer_id,
    pb.country_id,
    pb.country_name,
    pb.city_name,
    pb.month_start,
    SUM(pb.payment_amount) AS month_total_amount,
    COUNT(*) AS payment_count,
    MAX(pb.payment_amount) AS max_payment_amount,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pb.film_store_id) AS distinct_payment_stores_count,
    SUM(CASE WHEN pb.film_store_id IS NULL THEN 0
             WHEN pb.film_store_id <> pb.customer_store_id THEN 1
             ELSE 0
        END) AS off_registration_store_payment_count,
    1.0 * SUM(CASE WHEN pb.film_store_id IS NULL THEN 0
                    WHEN pb.film_store_id <> pb.customer_store_id THEN 1
                    ELSE 0
               END) / COUNT(*) AS off_registration_store_payment_share
  FROM payment_base AS pb
  GROUP BY
    pb.customer_id,
    pb.country_id,
    pb.country_name,
    pb.city_name,
    pb.month_start
),
monthly_with_prev3 AS (
  SELECT
    mcm.*,
    AVG(mcm.month_total_amount) OVER (
      PARTITION BY mcm.customer_id
      ORDER BY mcm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev3_month_avg_amount
  FROM monthly_customer_metrics AS mcm
),
eligible_customers_month AS (
  SELECT
    mwp.*,
    (
      SELECT COUNT(DISTINCT fcp2.category_id)
      FROM film_category_payments AS fcp2
      JOIN pay AS p2
        ON p2.p01 = fcp2.payment_id
      WHERE p2.p02 = mwp.customer_id
        AND date(p2.p06, 'start of month') = mwp.month_start
    ) AS distinct_categories_count
  FROM monthly_with_prev3 AS mwp
)
SELECT
  e.customer_id,
  e.country_name AS country,
  e.city_name AS city,
  strftime('%Y-%m', e.month_start) AS month,
  ROUND(e.month_total_amount, 2) AS payments_sum,
  e.payment_count,
  ROUND(e.max_payment_amount, 2) AS max_single_payment,
  ROUND(e.off_registration_store_payment_share, 4) AS off_registration_store_payment_share,
  RANK() OVER (
    PARTITION BY e.country_id, e.month_start
    ORDER BY e.month_total_amount DESC
  ) AS country_month_rank
FROM eligible_customers_month AS e
WHERE e.prev3_month_avg_amount IS NOT NULL
  AND e.prev3_month_avg_amount > 0
  AND e.month_total_amount > 3.0 * e.prev3_month_avg_amount
  AND e.distinct_staff_count >= 2
  AND e.distinct_categories_count >= 3
ORDER BY
  e.month_start,
  e.country_name,
  country_month_rank,
  e.customer_id;