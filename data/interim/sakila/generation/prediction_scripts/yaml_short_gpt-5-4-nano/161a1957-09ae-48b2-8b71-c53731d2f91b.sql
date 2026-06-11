WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country,
    ct.d02 AS city
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt ON cnt.c01 = ct.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    cg.first_name,
    cg.last_name,
    cg.country,
    cg.city,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  JOIN customer_geo cg ON cg.customer_id = p.p02
  JOIN stf s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02, cg.first_name, cg.last_name, cg.country, cg.city, date(p.p06)
),
pay_daily_with_avg AS (
  SELECT
    pd.*,
    (
      SELECT AVG(pd2.day_amount)
      FROM pay_daily pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.payment_date >= date(pd.payment_date, '-30 days')
        AND pd2.payment_date < pd.payment_date
    ) AS avg_prev_30d
  FROM pay_daily pd
),
country_p95 AS (
  -- empirical 95th percentile of daily sums among customers within the same country
  SELECT
    country,
    day_amount AS p95_daily_amount
  FROM (
    SELECT
      country,
      day_amount,
      ROW_NUMBER() OVER (PARTITION BY country ORDER BY day_amount) AS rn,
      COUNT(*) OVER (PARTITION BY country) AS cnt
    FROM pay_daily
  ) x
  WHERE rn >= CAST((95.0 * cnt + 99) / 100 AS INTEGER)
  -- if multiple rows satisfy, take the minimum qualifying value
  ORDER BY country, p95_daily_amount
),
country_p95_one AS (
  SELECT country, MIN(p95_daily_amount) AS p95_daily_amount
  FROM country_p95
  GROUP BY country
),
filtered AS (
  SELECT
    pd.customer_id,
    pd.first_name,
    pd.last_name,
    pd.country,
    pd.city,
    pd.payment_date,
    pd.payment_count,
    pd.day_amount,
    pd.staff_count,
    pd.store_count,
    c95.p95_daily_amount,
    pd.day_amount - pd.avg_prev_30d AS deviation_from_avg,
    pd.day_amount / pd.avg_prev_30d AS ratio_vs_avg
  FROM pay_daily_with_avg pd
  JOIN country_p95_one c95
    ON c95.country = pd.country
  WHERE pd.payment_count >= 3
    AND (pd.staff_count >= 2 OR pd.store_count >= 2)
    AND pd.avg_prev_30d IS NOT NULL
    AND pd.avg_prev_30d > 0
    AND pd.day_amount > 2.0 * pd.avg_prev_30d
    AND pd.day_amount > c95.p95_daily_amount
),
ranked AS (
  SELECT
    f.*,
    RANK() OVER (
      PARTITION BY f.country, f.customer_id
      ORDER BY f.day_amount DESC
    ) AS suspicious_rank_customer
  FROM filtered f
)
SELECT
  customer_id,
  first_name,
  last_name,
  country,
  city,
  payment_date AS spike_date,
  payment_count,
  ROUND(day_amount, 2) AS day_amount,
  staff_count,
  store_count,
  ROUND(deviation_from_avg, 2) AS deviation_from_prev_30d_avg,
  suspicious_rank_customer
FROM ranked
ORDER BY
  country,
  suspicious_rank_customer,
  day_amount DESC,
  customer_id,
  spike_date;