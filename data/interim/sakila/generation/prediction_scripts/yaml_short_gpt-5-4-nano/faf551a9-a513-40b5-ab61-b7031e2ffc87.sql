SELECT AVG(CAST(x.day_sum AS REAL))
      FROM payment_day_sums AS x
      WHERE x.customer_id = pds.customer_id
        AND x.payment_day >= DATE(pds.payment_day, '-30 day')
        AND x.payment_day < pds.payment_day
    ) AS avg_prev_30d
  FROM payment_day_sums AS pds
  JOIN customer_geo AS cg
    ON cg.customer_id = pds.customer_id
),
country_95_percentile AS (
  SELECT
    country_name,
    day_sum AS p95_day_sum
  FROM (
    SELECT
      wpa.country_name,
      wpa.day_sum,
      ROW_NUMBER() OVER (
        PARTITION BY wpa.country_name
        ORDER BY wpa.day_sum
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY wpa.country_name
      ) AS cnt
    FROM (
      SELECT
        cg.country_name,
        pds.payment_day,
        pds.customer_id,
        SUM(CAST(pds.day_sum AS REAL)) AS day_sum
      FROM payment_day_sums AS pds
      JOIN customer_geo AS cg
        ON cg.customer_id = pds.customer_id
      GROUP BY
        cg.country_name,
        pds.payment_day,
        pds.customer_id
    ) AS wpa
  )
  WHERE rn >= ((95 * cnt + 99) / 100)
),
candidate_spikes AS (
  SELECT
    wpa.customer_id,
    wpa.first_name,
    wpa.last_name,
    wpa.country_name,
    wpa.city_name,
    wpa.store_id,
    wpa.payment_day AS spike_date,
    wpa.payment_count,
    wpa.day_sum AS spike_day_sum,
    wpa.avg_prev_30d,
    (wpa.day_sum - wpa.avg_prev_30d) AS deviation_from_prev_avg,
    (
      SELECT cp.p95_day_sum
      FROM country_95_percentile AS cp
      WHERE cp.country_name = wpa.country_name
      LIMIT 1
    ) AS country_p95_day_sum
  FROM with_prev_avg AS wpa
  WHERE wpa.avg_prev_30d IS NOT NULL
    AND wpa.avg_prev_30d > 0
    AND wpa.day_sum >= 3 * wpa.avg_prev_30d
),
ranked AS (
  SELECT
    cs.*,
    DENSE_RANK() OVER (
      PARTITION BY cs.country_name
      ORDER BY cs.spike_day_sum DESC, cs.customer_id
    ) AS spike_amount_rank_in_country
  FROM candidate_spikes AS cs
  WHERE cs.spike_day_sum >= cs.country_p95_day_sum
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name AS country,
  city_name AS city,
  store_id AS store_id,
  spike_date,
  payment_count AS payments_in_spike_day,
  ROUND(spike_day_sum, 2) AS day_sum,
  ROUND(avg_prev_30d, 2) AS avg_prev_30d,
  ROUND(deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  spike_amount_rank_in_country AS spike_rank_in_country
FROM ranked
ORDER BY
  country,
  spike_rank_in_country,
  spike_date,
  customer_id;