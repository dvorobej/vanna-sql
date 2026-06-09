WITH
rental_payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p06 AS payment_datetime,
    date(p.p06, 'start of month') AS month_start,

    c.h02 AS customer_store_id,
    c.h01 AS customer_pk,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    c.h06 AS customer_address_id,

    cnt.c02 AS customer_country,
    ci.d02 AS customer_city,

    i.n03 AS rental_store_id,
    i.n02 AS film_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ci.d03
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
),
monthly_customer_store AS (
  SELECT
    customer_id,
    customer_store_id,
    customer_country,
    customer_city,
    rental_store_id,
    month_start,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_payment_sum,
    COUNT(DISTINCT staff_id) AS distinct_staff_count
  FROM rental_payment_base
  GROUP BY
    customer_id,
    customer_store_id,
    customer_country,
    customer_city,
    rental_store_id,
    month_start
),
monthly_customer_store_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months_sum,
    COUNT(mc.month_payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_prev_months_cnt
  FROM monthly_customer_store AS mc
),
country_store_month_rank AS (
  SELECT
    mc.*,
    PERCENT_RANK() OVER (
      PARTITION BY mc.rental_store_id, mc.customer_country, mc.month_start
      ORDER BY mc.month_payment_sum DESC
    ) AS pct_rank_within_store_country
  FROM monthly_customer_store_with_history AS mc
),
return_delay_flags AS (
  SELECT
    p.p02 AS customer_id,
    i.n03 AS rental_store_id,
    date(p.p06, 'start of month') AS month_start,

    SUM(
      CASE
        WHEN r.q05 IS NOT NULL
         AND julianday(r.q05) - julianday(r.q02) > f.i07
        THEN 1.0 ELSE 0.0
      END
    ) AS return_delayed_payment_count,

    COUNT(*) * 1.0 AS total_payment_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flm AS f
    ON f.i01 = i.n02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    i.n03,
    date(p.p06, 'start of month')
),
rank_customer_within_store_month AS (
  SELECT
    mc.*,
    RANK() OVER (
      PARTITION BY mc.rental_store_id, mc.customer_country, mc.month_start
      ORDER BY mc.month_payment_sum DESC
    ) AS customer_store_month_rank
  FROM country_store_month_rank AS mc
)
SELECT
  r.rental_store_id AS store_id,
  r.customer_country AS country,
  r.customer_city AS city,
  r.customer_id,
  r.month_start AS month,
  ROUND(r.month_payment_sum, 2) AS month_payment_sum,
  r.payment_count,
  r.distinct_staff_count,
  ROUND(
    (rd.return_delayed_payment_count / NULLIF(rd.total_payment_count, 0)),
    4
  ) AS return_delay_payment_share,
  r.customer_store_month_rank
FROM rank_customer_within_store_month AS r
LEFT JOIN return_delay_flags AS rd
  ON rd.customer_id = r.customer_id
 AND rd.rental_store_id = r.rental_store_id
 AND rd.month_start = r.month_start
WHERE r.personal_prev_months_cnt >= 1
  AND r.personal_avg_prev_months_sum > 0
  AND r.month_payment_sum >= 3.0 * r.personal_avg_prev_months_sum
  AND r.pct_rank_within_store_country <= 0.05
ORDER BY
  r.month_start,
  r.rental_store_id,
  r.customer_country,
  r.month_payment_sum DESC,
  r.customer_id;