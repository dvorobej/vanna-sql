WITH
payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p04 AS rental_key,
    c.h02 AS customer_store_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    r.q07 AS rental_last_update, -- not used, but keeps join visibility
    r.q02 AS rental_date,
    r.q05 AS return_date,
    i.n03 AS issuing_store_id
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr ca
    ON ca.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = ca.e05
  JOIN cnt co
    ON co.c01 = ci.d03
  JOIN inv i
    ON i.n01 = r.q03
  WHERE p.p06 >= '2000-01-01'
),
monthly_customer AS (
  SELECT
    customer_id,
    month_start,
    customer_store_id,
    country_id,
    country_name,
    city_name,
    SUM(payment_amount) AS month_payment_sum,
    COUNT(*) AS month_payment_count,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    SUM(
      CASE
        WHEN return_date IS NOT NULL
         AND (julianday(return_date) - julianday(rental_date)) > flm.i07
        THEN 1
        ELSE 0
      END
    ) AS late_return_payment_count
  FROM payment_base
  JOIN ren r
    ON r.q01 = payment_base.rental_key
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flm
    ON flm.i01 = i.n02
  GROUP BY
    customer_id,
    month_start,
    customer_store_id,
    country_id,
    country_name,
    city_name
),
monthly_customer_with_prev AS (
  SELECT
    mc.*,
    AVG(month_payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months_sum
  FROM monthly_customer mc
),
store_country_month_ranked AS (
  SELECT
    mcwp.*,
    PERCENT_RANK() OVER (
      PARTITION BY customer_store_id, country_id, month_start
      ORDER BY month_payment_sum DESC
    ) AS pct_rank_within_store_country_month
  FROM monthly_customer_with_prev mcwp
),
store_country_month_thresholded AS (
  SELECT
    scm.*,
    RANK() OVER (
      PARTITION BY customer_store_id, country_id, month_start
      ORDER BY month_payment_sum DESC
    ) AS rank_in_store_country_month,
    COUNT(*) OVER (
      PARTITION BY customer_store_id, country_id, month_start
    ) AS customers_in_group
  FROM store_country_month_ranked scm
),
top_store_month_rank AS (
  SELECT
    scm.*,
    RANK() OVER (
      PARTITION BY customer_store_id, month_start
      ORDER BY month_payment_sum DESC
    ) AS customer_store_month_amount_rank
  FROM store_country_month_thresholded scm
)
SELECT
  t.customer_id,
  t.country_name,
  t.city_name,
  t.customer_store_id AS store_id,
  strftime('%Y-%m', t.month_start) AS month,
  ROUND(t.month_payment_sum, 2) AS month_payment_sum,
  t.month_payment_count AS month_payment_count,
  t.distinct_staff_count AS distinct_staff_count,
  ROUND(
    1.0 * t.late_return_payment_count / NULLIF(t.month_payment_count, 0),
    4
  ) AS late_return_payment_share,
  t.customer_store_month_amount_rank AS customer_store_month_amount_rank
FROM top_store_month_rank t
WHERE t.personal_avg_prev_months_sum IS NOT NULL
  AND t.personal_avg_prev_months_sum > 0
  AND t.month_payment_sum >= 3.0 * t.personal_avg_prev_months_sum
  AND t.pct_rank_within_store_country_month <= 0.05
ORDER BY
  t.month_start,
  t.country_name,
  t.customer_store_id,
  t.customer_store_month_amount_rank,
  t.customer_id;