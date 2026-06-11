WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    CAST(p.p05 AS REAL) AS amount,
    p.p04 AS rental_id,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    cu.h02 AS home_store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name,
    st.o07 AS staff_store_id,
    CASE
      WHEN r.q05 IS NULL THEN 0
      WHEN julianday(r.q05) - julianday(r.q02) > COALESCE(f.i07, 0) THEN 1
      ELSE 0
    END AS is_return_late
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  JOIN cus cu
    ON cu.h01 = p.p02
  JOIN adr a
    ON a.e01 = cu.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ci.d03
  JOIN stf st
    ON st.o01 = p.p03
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flm f
    ON f.i01 = i.n02
),
monthly_customer AS (
  SELECT
    customer_id,
    home_store_id,
    country_id,
    country_name,
    city_name,
    month_start,
    COUNT(payment_id) AS payment_count,
    SUM(amount) AS payment_sum,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    AVG(is_return_late * 1.0) AS late_return_payment_share
  FROM payment_base
  GROUP BY
    customer_id,
    home_store_id,
    country_id,
    country_name,
    city_name,
    month_start
),
monthly_prev_avg AS (
  SELECT
    mc.*,
    AVG(payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_payment_sum
  FROM monthly_customer mc
),
store_country_month_thresholds AS (
  SELECT
    home_store_id,
    country_id,
    month_start,
    PERCENT_RANK() OVER (
      PARTITION BY home_store_id, country_id, month_start
      ORDER BY payment_sum DESC
    ) AS pr_desc
  FROM monthly_prev_avg
),
joined AS (
  SELECT
    mpa.*,
    stct.pr_desc
  FROM monthly_prev_avg mpa
  JOIN store_country_month_thresholds stct
    ON stct.home_store_id = mpa.home_store_id
   AND stct.country_id = mpa.country_id
   AND stct.month_start = mpa.month_start
   AND stct.payment_sum = mpa.payment_sum
)
SELECT
  j.customer_id,
  j.country_name AS country,
  j.city_name AS city,
  j.home_store_id AS store_id,
  strftime('%Y-%m', j.month_start) AS payment_month,
  ROUND(j.payment_sum, 2) AS payment_sum,
  j.payment_count,
  j.distinct_staff_count AS distinct_staff_count,
  ROUND(j.late_return_payment_share, 4) AS late_return_payment_share,
  RANK() OVER (
    PARTITION BY j.home_store_id, j.month_start
    ORDER BY j.payment_sum DESC
  ) AS customer_store_month_rank
FROM joined j
WHERE
  j.prev_months_avg_payment_sum IS NOT NULL
  AND j.prev_months_avg_payment_sum > 0
  AND j.payment_sum >= 3 * j.prev_months_avg_payment_sum
  AND j.payment_sum > 0
  AND j.pr_desc <= 0.05
ORDER BY
  j.month_start,
  j.country_name,
  j.home_store_id,
  j.payment_sum DESC,
  j.customer_id;