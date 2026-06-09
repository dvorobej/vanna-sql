WITH payment_day_details AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    p.p06 AS payment_ts,
    DATE(p.p06) AS payment_date,
    p.p03 AS staff_id,
    c.h02 AS home_store_id,
    p.p01 AS payment_id,
    CAST(p.p05 AS REAL) AS amount,
    s.o07 AS store_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  JOIN stf AS s
    ON s.o01 = p.p03
),
daily_customer_pay AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    country_name,
    city_name,
    payment_date,
    COUNT(*) AS payment_count,
    SUM(amount) AS day_total_amount,
    COUNT(DISTINCT store_id) AS distinct_stores,
    COUNT(DISTINCT staff_id) AS distinct_staff
  FROM payment_day_details
  GROUP BY
    customer_id, first_name, last_name, country_name, city_name, payment_date
),
daily_customer_with_prev AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_total_amount)
      FROM daily_customer_pay AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= DATE(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_daily_prev_30
  FROM daily_customer_pay AS d
),
country_day_quantiles AS (
  SELECT
    country_name,
    payment_date,
    day_total_amount,
    ROW_NUMBER() OVER (
      PARTITION BY country_name
      ORDER BY day_total_amount
    ) AS rn,
    COUNT(*) OVER (PARTITION BY country_name) AS cnt
  FROM daily_customer_pay
),
country_p95 AS (
  SELECT
    country_name,
    MAX(day_total_amount) AS p95_day_total_amount
  FROM country_day_quantiles
  WHERE rn >= ((95 * cnt + 99) / 100)
  GROUP BY country_name
),
spike_candidates AS (
  SELECT
    d.*,
    cp.p95_day_total_amount,
    d.day_total_amount - d.avg_daily_prev_30 AS deviation_from_avg_prev_30,
    d.day_total_amount / NULLIF(d.avg_daily_prev_30, 0) AS spike_ratio
  FROM daily_customer_with_prev AS d
  JOIN country_p95 AS cp
    ON cp.country_name = d.country_name
  WHERE d.avg_daily_prev_30 IS NOT NULL
    AND d.avg_daily_prev_30 > 0
    AND d.payment_count >= 1
    AND d.day_total_amount >= 3.0 * d.avg_daily_prev_30
    AND d.day_total_amount >= cp.p95_day_total_amount
),
ranked_spikes AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY s.country_name
      ORDER BY s.day_total_amount DESC, s.payment_date DESC, s.customer_id
    ) AS spike_rank_in_country
  FROM spike_candidates AS s
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name,
  city_name,
  payment_date AS spike_date,
  distinct_stores AS stores_count_on_spike_day,
  payment_count,
  ROUND(day_total_amount, 2) AS day_total_amount,
  ROUND(avg_daily_prev_30, 2) AS avg_daily_prev_30,
  ROUND(deviation_from_avg_prev_30, 2) AS deviation_from_avg_prev_30,
  ROUND(p95_day_total_amount, 2) AS country_p95_daily_amount,
  spike_rank_in_country
FROM ranked_spikes
ORDER BY
  country_name,
  spike_rank_in_country,
  day_total_amount DESC,
  payment_date DESC,
  customer_id;