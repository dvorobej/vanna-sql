SELECT AVG(d2.total_amount)
      FROM daily_agg AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= DATE(d.day_date, '-30 days')
        AND d2.day_date < d.day_date
    ), 0.0) AS personal_avg_prev_30d
  FROM daily_agg AS d
),
daily_rank_by_country AS (
  SELECT
    dwp.*,
    (
      SELECT AVG(dcp.total_amount)
      FROM (
        SELECT
          d2.day_date,
          d2.total_amount,
          ROW_NUMBER() OVER (PARTITION BY d2.country_name ORDER BY d2.total_amount) AS rn,
          COUNT(*) OVER (PARTITION BY d2.country_name) AS cnt_days
        FROM daily_agg AS d2
      ) AS dcp
      WHERE dcp.country_name = dwp.country_name
        AND dcp.rn >= ((95 * dcp.cnt_days + 99) / 100)
    ) AS country_p95_amount
  FROM daily_with_personal_avg AS dwp
),
filtered AS (
  SELECT
    *
  FROM daily_rank_by_country
  WHERE personal_avg_prev_30d > 0
    AND total_amount >= 3.0 * personal_avg_prev_30d
    AND payment_count >= 3
    AND staff_count >= 2
    AND total_amount > COALESCE(country_p95_amount, -1e18)
),
ranked AS (
  SELECT
    f.*,
    RANK() OVER (
      PARTITION BY f.country_name
      ORDER BY (f.total_amount / NULLIF(f.personal_avg_prev_30d, 0)) DESC
    ) AS country_suspicion_rank
  FROM filtered AS f
)
SELECT
  customer_id AS h01,
  city_name AS d02,
  country_name AS c02,
  day_date AS p06,
  payment_count,
  ROUND(total_amount, 2) AS total_amount,
  staff_count,
  store_count,
  min_payment_ts AS min_payment_time,
  max_payment_ts AS max_payment_time,
  ROUND(max_payment_amount, 2) AS max_payment,
  country_suspicion_rank
FROM ranked
ORDER BY
  country_name,
  country_suspicion_rank,
  total_amount DESC,
  day_date,
  customer_id;