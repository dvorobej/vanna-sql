WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    country.c02 AS country,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    p.p05 AS amount,
    p.p06 AS payment_ts,
    date(p.p06) AS payment_day,
    date(p.p06, 'start of month') AS payment_month
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS country
    ON country.c01 = city.d03
  JOIN stf AS s
    ON s.o01 = p.p03
),
monthly_customer AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    country,
    payment_month,
    COUNT(*) AS payment_count,
    SUM(amount) AS monthly_amount
  FROM payment_base
  GROUP BY
    customer_id,
    first_name,
    last_name,
    country,
    payment_month
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(monthly_amount) OVER (
      PARTITION BY customer_id
      ORDER BY payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_monthly_amount,
    AVG(payment_count * 1.0) OVER (
      PARTITION BY customer_id
      ORDER BY payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_monthly_count
  FROM monthly_customer AS mc
),
country_month_stats AS (
  SELECT
    country,
    payment_month,
    AVG(monthly_amount) AS country_avg_monthly_amount
  FROM monthly_customer
  GROUP BY
    country,
    payment_month
),
country_month_ranked AS (
  SELECT
    mc.customer_id,
    mc.country,
    mc.payment_month,
    RANK() OVER (
      PARTITION BY mc.country, mc.payment_month
      ORDER BY mc.monthly_amount DESC
    ) AS country_amount_rank,
    COUNT(*) OVER (
      PARTITION BY mc.country, mc.payment_month
    ) AS country_customer_count
  FROM monthly_customer AS mc
),
daily_distribution AS (
  SELECT
    customer_id,
    payment_month,
    payment_day,
    COUNT(*) AS daily_payment_count,
    SUM(amount) AS daily_amount,
    COUNT(DISTINCT staff_id) AS daily_staff_count,
    COUNT(DISTINCT store_id) AS daily_store_count
  FROM payment_base
  GROUP BY
    customer_id,
    payment_month,
    payment_day
),
monthly_daily_distribution AS (
  SELECT
    customer_id,
    payment_month,
    MAX(daily_staff_count) AS max_daily_staff_count,
    MAX(daily_store_count) AS max_daily_store_count,
    SUM(CASE WHEN daily_staff_count >= 2 OR daily_store_count >= 2 THEN 1 ELSE 0 END) AS multi_staff_or_store_days
  FROM daily_distribution
  GROUP BY
    customer_id,
    payment_month
),
series_24h AS (
  SELECT DISTINCT
    p1.customer_id,
    p1.payment_month
  FROM payment_base AS p1
  JOIN payment_base AS p2
    ON p2.customer_id = p1.customer_id
   AND p2.payment_ts >= p1.payment_ts
   AND p2.payment_ts < datetime(p1.payment_ts, '+1 day')
  GROUP BY
    p1.customer_id,
    p1.payment_month,
    p1.payment_id
  HAVING COUNT(*) >= 3
     AND COUNT(DISTINCT p2.staff_id) >= 2
),
scored AS (
  SELECT
    h.customer_id,
    h.first_name,
    h.last_name,
    h.country,
    h.payment_month,
    h.payment_count,
    h.monthly_amount,
    h.personal_avg_monthly_amount,
    h.personal_avg_monthly_count,
    cms.country_avg_monthly_amount,
    cmr.country_amount_rank,
    cmr.country_customer_count,
    COALESCE(mdd.max_daily_staff_count, 0) AS max_daily_staff_count,
    COALESCE(mdd.max_daily_store_count, 0) AS max_daily_store_count,
    COALESCE(mdd.multi_staff_or_store_days, 0) AS multi_staff_or_store_days,
    CASE WHEN s24.customer_id IS NOT NULL THEN 1 ELSE 0 END AS has_3_payments_24h_multi_staff
  FROM monthly_with_history AS h
  JOIN country_month_stats AS cms
    ON cms.country = h.country
   AND cms.payment_month = h.payment_month
  JOIN country_month_ranked AS cmr
    ON cmr.customer_id = h.customer_id
   AND cmr.country = h.country
   AND cmr.payment_month = h.payment_month
  LEFT JOIN monthly_daily_distribution AS mdd
    ON mdd.customer_id = h.customer_id
   AND mdd.payment_month = h.payment_month
  LEFT JOIN series_24h AS s24
    ON s24.customer_id = h.customer_id
   AND s24.payment_month = h.payment_month
)
SELECT
  customer_id,
  first_name || ' ' || last_name AS customer_name,
  country,
  payment_month AS month,
  ROUND(monthly_amount, 2) AS monthly_amount,
  payment_count,
  ROUND(monthly_amount / personal_avg_monthly_amount, 2) AS personal_amount_ratio,
  ROUND(payment_count / personal_avg_monthly_count, 2) AS personal_count_ratio,
  ROUND(monthly_amount - personal_avg_monthly_amount, 2) AS personal_amount_deviation,
  ROUND(monthly_amount / country_avg_monthly_amount, 2) AS country_amount_ratio,
  ROUND(monthly_amount - country_avg_monthly_amount, 2) AS country_amount_deviation,
  max_daily_staff_count,
  max_daily_store_count,
  multi_staff_or_store_days,
  has_3_payments_24h_multi_staff
FROM scored
WHERE personal_avg_monthly_amount > 0
  AND personal_avg_monthly_count > 0
  AND monthly_amount >= personal_avg_monthly_amount * 3
  AND payment_count >= personal_avg_monthly_count * 3
  AND (
    country_amount_rank <= MAX(1, CAST(country_customer_count * 0.05 + 0.999999 AS INTEGER))
    OR has_3_payments_24h_multi_staff = 1
  )
ORDER BY
  personal_amount_ratio DESC,
  country_amount_ratio DESC,
  monthly_amount DESC;