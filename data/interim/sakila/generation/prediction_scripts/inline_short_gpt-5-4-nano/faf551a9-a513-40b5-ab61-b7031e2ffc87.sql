WITH daily_customer_payment AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    ct.d02 AS city_name,
    p.p03 AS staff_id,
    COALESCE(st.o07, c.h02) AS store_id,
    DATE(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS day_amount
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
  LEFT JOIN stf AS st
    ON st.o01 = p.p03
  GROUP BY
    p.p02,
    c.h03, c.h04,
    cnt.c02,
    ct.d02,
    COALESCE(st.o07, c.h02),
    p.p03,
    DATE(p.p06)
),
daily_with_prev_avg AS (
  SELECT
    d.*,
    (
      SELECT AVG(p30.day_amount)
      FROM daily_customer_payment AS p30
      WHERE p30.customer_id = d.customer_id
        AND p30.day_date >= date(d.day_date, '-30 day')
        AND p30.day_date < d.day_date
    ) AS avg_prev_30d,
    (
      SELECT AVG(p30.day_amount)
      FROM daily_customer_payment AS p30
      WHERE p30.customer_id = d.customer_id
        AND p30.day_date >= date(d.day_date, '-30 day')
        AND p30.day_date < d.day_date
    ) AS avg_prev_30d_again
  FROM daily_customer_payment AS d
),
country_days_ranked AS (
  SELECT
    dc.country_name,
    dc.day_amount,
    dc.day_date,
    dc.customer_id,
    ROW_NUMBER() OVER (
      PARTITION BY dc.country_name
      ORDER BY dc.day_amount
    ) AS rn,
    COUNT(*) OVER (PARTITION BY dc.country_name) AS cnt_days
  FROM daily_customer_payment AS dc
),
country_p95 AS (
  SELECT
    country_name,
    MAX(day_amount) AS p95_day_amount
  FROM country_days_ranked
  WHERE rn >= ((95 * cnt_days + 99) / 100)
  GROUP BY country_name
),
spikes AS (
  SELECT
    d.day_date AS spike_date,
    d.first_name,
    d.last_name,
    d.country_name,
    d.city_name,
    d.store_id,
    d.payment_count,
    ROUND(d.day_amount, 2) AS day_amount,
    ROUND(d.avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(d.day_amount - d.avg_prev_30d, 2) AS deviation_from_avg,
    ROUND(d.day_amount / NULLIF(d.avg_prev_30d, 0), 2) AS spike_ratio_vs_avg,
    cp.p95_day_amount,
    RANK() OVER (
      PARTITION BY d.country_name
      ORDER BY d.day_amount DESC, d.customer_id
    ) AS spike_rank_in_country
  FROM daily_with_prev_avg AS d
  JOIN country_p95 AS cp
    ON cp.country_name = d.country_name
  WHERE d.avg_prev_30d IS NOT NULL
    AND d.avg_prev_30d > 0
    AND d.day_amount >= d.avg_prev_30d * 3
    AND d.day_amount >= cp.p95_day_amount
)
SELECT
  s.spike_date,
  s.first_name,
  s.last_name,
  s.country_name,
  s.city_name,
  s.store_id,
  s.payment_count,
  s.day_amount,
  s.avg_prev_30d,
  s.deviation_from_avg,
  s.spike_rank_in_country
FROM spikes AS s
ORDER BY
  s.country_name,
  s.spike_rank_in_country,
  s.spike_date,
  s.last_name,
  s.first_name;