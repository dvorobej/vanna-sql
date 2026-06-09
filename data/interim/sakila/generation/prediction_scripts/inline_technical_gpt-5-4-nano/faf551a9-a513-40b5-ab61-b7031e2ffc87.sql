SELECT AVG(da_prev.day_amount)
      FROM daily_agg AS da_prev
      WHERE da_prev.customer_id = da.customer_id
        AND da_prev.payment_date >= date(da.payment_date, '-30 days')
        AND da_prev.payment_date < da.payment_date
    ) AS personal_avg_prev_30d
  FROM daily_agg AS da
),
with_country_p95 AS (
  SELECT
    wpa.*,
    (
      SELECT
        MAX(x.day_amount)
      FROM (
        SELECT
          d2.day_amount,
          NTILE(100) OVER (PARTITION BY d2.country_id ORDER BY d2.day_amount) AS pct_bucket
        FROM daily_agg AS d2
        WHERE d2.country_id = wpa.country_id
      ) AS x
      WHERE x.pct_bucket = 100
    ) AS country_p95_day_amount
  FROM with_personal_avg AS wpa
),
filtered AS (
  SELECT
    wcp.customer_id,
    wcp.store_id,
    wcp.first_name,
    wcp.last_name,
    wcp.country_id,
    wcp.country_name,
    wcp.city_name,
    wcp.payment_date,
    wcp.payment_count,
    wcp.day_amount,
    wcp.personal_avg_prev_30d,
    (wcp.day_amount - wcp.personal_avg_prev_30d) AS deviation_from_avg,
    CASE
      WHEN wcp.personal_avg_prev_30d IS NULL OR wcp.personal_avg_prev_30d = 0 THEN NULL
      ELSE wcp.day_amount / wcp.personal_avg_prev_30d
    END AS spike_ratio
  FROM with_country_p95 AS wcp
  WHERE wcp.personal_avg_prev_30d IS NOT NULL
    AND wcp.personal_avg_prev_30d > 0
    AND wcp.day_amount >= 3 * wcp.personal_avg_prev_30d
    AND wcp.day_amount > wcp.country_p95_day_amount
)
SELECT
  payment_date AS spike_date,
  customer_id AS customer_h01,
  first_name AS cus_h03,
  last_name AS cus_h04,
  country_name AS cnt_c02,
  city_name AS cty_d02,
  store_id AS cus_h02_store_id,
  payment_count AS payments_in_day,
  ROUND(day_amount, 2) AS day_amount,
  ROUND(personal_avg_prev_30d, 2) AS avg_prev_30_days,
  ROUND(deviation_from_avg, 2) AS deviation_from_avg,
  RANK() OVER (
    PARTITION BY country_id
    ORDER BY day_amount DESC
  ) AS country_spike_rank
FROM (
  SELECT
    f.*,
    f.personal_avg_prev_30d
  FROM filtered AS f
) AS t
ORDER BY
  country_spike_rank,
  day_amount DESC,
  payment_date,
  customer_h01;