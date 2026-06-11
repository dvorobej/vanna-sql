SELECT AVG(d2.day_amount)
      FROM daily_by_customer AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.spike_day >= date(d.spike_day, '-30 day')
        AND d2.spike_day < d.spike_day
    ) AS personal_avg_prev_30d
  FROM daily_by_customer AS d
  -- keep only days where personal history exists
),
country_day_ranked AS (
  SELECT
    d.*,
    PERCENT_RANK() OVER (
      PARTITION BY d.country_id, d.spike_day
      ORDER BY d.day_amount
    ) AS pr_dummy
  FROM daily_with_personal_avg AS d
),
country_p95 AS (
  /* For each country, compute the 95th percentile threshold from all daily totals.
     Uses nearest-rank: rank >= ceil(0.95 * N). */
  SELECT
    country_id,
    day_p95_amount
  FROM (
    SELECT
      country_id,
      day_amount,
      ROW_NUMBER() OVER (PARTITION BY country_id ORDER BY day_amount) AS rn,
      COUNT(*) OVER (PARTITION BY country_id) AS cnt_days
    FROM daily_by_customer
  ) AS x
  WHERE rn >= CAST((0.95 * cnt_days + 0.999999) AS INT)
  ORDER BY rn
  LIMIT 1
),
qualified_days AS (
  SELECT
    d.*
  FROM daily_with_personal_avg AS d
  JOIN country_p95 AS p95
    ON p95.country_id = d.country_id
  WHERE d.personal_avg_prev_30d IS NOT NULL
    AND d.personal_avg_prev_30d > 0
    AND d.day_amount >= 3.0 * d.personal_avg_prev_30d
    AND d.day_amount > p95.day_p95_amount
),
ranked_in_country AS (
  SELECT
    q.*,
    RANK() OVER (
      PARTITION BY q.country_id
      ORDER BY q.day_amount DESC
    ) AS country_spike_rank_in_amount
  FROM qualified_days AS q
)
SELECT
  qc.customer_id,
  qc.customer_first_name AS h03,
  qc.customer_last_name AS h04,
  qc.country_name AS c02,
  qc.city_name AS d02,
  qc.customer_store_id AS customer_store_id,
  qc.payment_count,
  ROUND(qc.day_amount, 2) AS day_amount,
  ROUND(qc.personal_avg_prev_30d, 2) AS avg_prev_30_days,
  ROUND(qc.day_amount - qc.personal_avg_prev_30d, 2) AS deviation_from_avg,
  qc.country_spike_rank_in_amount AS country_spike_rank,
  qc.spike_day AS spike_date
FROM ranked_in_country AS qc
ORDER BY
  qc.country_name,
  qc.country_spike_rank_in_amount,
  qc.day_amount DESC,
  qc.customer_id,
  qc.spike_day;