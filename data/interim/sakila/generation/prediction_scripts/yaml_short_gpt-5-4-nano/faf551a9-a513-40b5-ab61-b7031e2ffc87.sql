SELECT AVG(dp2.day_amount)
      FROM daily_payments AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_day >= DATE(dp.payment_day, '-30 days')
        AND dp2.payment_day < dp.payment_day
    ) AS avg_daily_prev_30d
  FROM daily_payments AS dp
),
flagged_days AS (
  SELECT
    d.*,
    (d.day_amount - d.avg_daily_prev_30d) AS deviation_from_avg,
    d.day_amount / NULLIF(d.avg_daily_prev_30d, 0) AS spike_ratio
  FROM daily_with_baseline AS d
  WHERE d.avg_daily_prev_30d IS NOT NULL
    AND d.avg_daily_prev_30d > 0
    AND d.day_amount >= 3 * d.avg_daily_prev_30d
),
country_p95 AS (
  SELECT country_name, day_amount
  FROM (
    SELECT
      country_name,
      day_amount,
      ROW_NUMBER() OVER (PARTITION BY country_name ORDER BY day_amount) AS rn,
      COUNT(*) OVER (PARTITION BY country_name) AS cnt
    FROM daily_payments
  ) x
  WHERE rn >= ((95 * cnt) + 99) / 100
),
country_p95_agg AS (
  SELECT
    country_name,
    MAX(day_amount) AS p95_day_amount
  FROM country_p95
  GROUP BY country_name
),
final_cases AS (
  SELECT
    fd.*,
    c95.p95_day_amount
  FROM flagged_days fd
  JOIN country_p95_agg c95
    ON c95.country_name = fd.country_name
  WHERE fd.day_amount >= c95.p95_day_amount
),
ranked AS (
  SELECT
    fc.*,
    RANK() OVER (
      PARTITION BY fc.country_name
      ORDER BY fc.day_amount DESC, fc.payment_day DESC, fc.customer_id
    ) AS spike_rank_in_country
  FROM final_cases fc
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name,
  city_name,
  store_id AS store,
  payment_day AS spike_date,
  payment_count,
  ROUND(day_amount, 2) AS day_amount,
  ROUND(avg_daily_prev_30d, 2) AS avg_daily_prev_30d,
  ROUND(deviation_from_avg, 2) AS deviation_from_avg,
  spike_rank_in_country
FROM ranked
ORDER BY
  country_name,
  spike_rank_in_country,
  spike_date,
  customer_id;