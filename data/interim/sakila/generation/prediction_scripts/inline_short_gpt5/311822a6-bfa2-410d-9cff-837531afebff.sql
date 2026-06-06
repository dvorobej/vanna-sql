WITH RECURSIVE
payment_bounds AS (
  SELECT
    date(MIN(p06)) AS min_day,
    date(MAX(p06)) AS max_day
  FROM pay
),
calendar(day_date) AS (
  SELECT min_day
  FROM payment_bounds
  WHERE min_day IS NOT NULL

  UNION ALL

  SELECT date(day_date, '+1 day')
  FROM calendar
  CROSS JOIN payment_bounds
  WHERE day_date < max_day
),
customer_dim AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 || ' ' || cus.h04 AS customer_name,
    cty.d02 AS city_name,
    cnt.c02 AS country_name
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
payment_detail AS (
  SELECT
    pay.p01 AS payment_id,
    pay.p02 AS customer_id,
    date(pay.p06) AS payment_day,
    CAST(pay.p05 AS REAL) AS payment_amount,
    pay.p03 AS staff_id,
    stf.o07 AS store_id
  FROM pay
  JOIN stf ON stf.o01 = pay.p03
),
daily_payments AS (
  SELECT
    customer_id,
    payment_day,
    SUM(payment_amount) AS daily_amount,
    COUNT(*) AS daily_count
  FROM payment_detail
  GROUP BY
    customer_id,
    payment_day
),
customer_calendar AS (
  SELECT
    cd.customer_id,
    cd.customer_name,
    cd.city_name,
    cd.country_name,
    cal.day_date,
    COALESCE(dp.daily_amount, 0.0) AS daily_amount,
    COALESCE(dp.daily_count, 0) AS daily_count
  FROM customer_dim AS cd
  CROSS JOIN calendar AS cal
  LEFT JOIN daily_payments AS dp
    ON dp.customer_id = cd.customer_id
   AND dp.payment_day = cal.day_date
),
rolling_7d AS (
  SELECT
    customer_calendar.*,
    date(day_date, '-6 days') AS window_start,
    day_date AS window_end,
    SUM(daily_amount) OVER (
      PARTITION BY customer_id
      ORDER BY day_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS window_amount,
    SUM(daily_count) OVER (
      PARTITION BY customer_id
      ORDER BY day_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS window_payment_count
  FROM customer_calendar
),
rolling_with_baseline AS (
  SELECT
    rolling_7d.*,
    COUNT(*) OVER (
      PARTITION BY customer_id
      ORDER BY day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS prev30_days_count,
    AVG(window_amount) OVER (
      PARTITION BY customer_id
      ORDER BY day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS prev30_avg_7d_amount,
    AVG(window_payment_count) OVER (
      PARTITION BY customer_id
      ORDER BY day_date
      ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
    ) AS prev30_avg_7d_payment_count
  FROM rolling_7d
),
window_staff_store AS (
  SELECT
    r.customer_id,
    r.window_end,
    COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pd.store_id) AS distinct_store_count
  FROM rolling_with_baseline AS r
  LEFT JOIN payment_detail AS pd
    ON pd.customer_id = r.customer_id
   AND pd.payment_day BETWEEN r.window_start AND r.window_end
  GROUP BY
    r.customer_id,
    r.window_end
),
suspicious_windows AS (
  SELECT
    strftime('%Y-%m', r.window_end) AS payment_month,
    r.customer_id,
    r.customer_name,
    r.city_name,
    r.country_name,
    r.window_start,
    r.window_end,
    r.window_amount,
    r.window_payment_count,
    r.prev30_avg_7d_amount,
    r.prev30_avg_7d_payment_count,
    wss.distinct_staff_count,
    wss.distinct_store_count,
    r.window_amount - r.prev30_avg_7d_amount AS amount_excess,
    r.window_payment_count - r.prev30_avg_7d_payment_count AS count_excess
  FROM rolling_with_baseline AS r
  JOIN window_staff_store AS wss
    ON wss.customer_id = r.customer_id
   AND wss.window_end = r.window_end
  WHERE r.prev30_days_count = 30
    AND r.prev30_avg_7d_amount > 0
    AND r.prev30_avg_7d_payment_count > 0
    AND r.window_amount >= r.prev30_avg_7d_amount * 3
    AND r.window_payment_count >= r.prev30_avg_7d_payment_count * 3
    AND (wss.distinct_staff_count > 1 OR wss.distinct_store_count > 1)
),
best_window_per_customer_month AS (
  SELECT *
  FROM (
    SELECT
      suspicious_windows.*,
      ROW_NUMBER() OVER (
        PARTITION BY payment_month, customer_id
        ORDER BY amount_excess DESC, window_amount DESC, window_payment_count DESC, window_end
      ) AS rn
    FROM suspicious_windows
  )
  WHERE rn = 1
)
SELECT
  payment_month,
  customer_id,
  customer_name,
  city_name,
  country_name,
  window_start,
  window_end,
  ROUND(window_amount, 2) AS window_amount,
  window_payment_count,
  ROUND(prev30_avg_7d_amount, 2) AS prev30_avg_7d_amount,
  ROUND(prev30_avg_7d_payment_count, 2) AS prev30_avg_7d_payment_count,
  ROUND(amount_excess, 2) AS amount_excess,
  ROUND(count_excess, 2) AS count_excess,
  distinct_staff_count,
  distinct_store_count,
  RANK() OVER (
    PARTITION BY payment_month
    ORDER BY amount_excess DESC, window_amount DESC, window_payment_count DESC
  ) AS monthly_excess_rank
FROM best_window_per_customer_month
ORDER BY
  payment_month,
  monthly_excess_rank,
  customer_id;