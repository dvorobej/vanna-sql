WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
daily AS (
  SELECT
    p.p02 AS customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_id,
    cg.country,
    cg.city,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum,
    COUNT(p.p01) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN customer_geo AS cg ON cg.customer_id = p.p02
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02, cg.first_name, cg.last_name,
    cg.country_id, cg.country, cg.city,
    date(p.p06)
),
daily_with_prev AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.daily_sum)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_prev_30
  FROM daily AS d
),
country_daily AS (
  SELECT
    country_id,
    daily_sum
  FROM daily
),
country_quantile_p95 AS (
  SELECT
    country_id,
    daily_sum
  FROM (
    SELECT
      country_id,
      daily_sum,
      ROW_NUMBER() OVER (PARTITION BY country_id ORDER BY daily_sum) AS rn,
      COUNT(*) OVER (PARTITION BY country_id) AS cnt
    FROM country_daily
  )
  WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
),
country_p95 AS (
  SELECT
    country_id,
    MIN(daily_sum) AS p95_daily_sum
  FROM country_quantile_p95
  GROUP BY country_id
),
suspicious AS (
  SELECT
    d.*,
    (d.daily_sum - d.avg_prev_30) AS deviation_from_avg,
    (d.daily_sum / d.avg_prev_30) AS ratio_vs_avg,
    cp.p95_daily_sum
  FROM daily_with_prev AS d
  JOIN country_p95 AS cp ON cp.country_id = d.country_id
  WHERE d.avg_prev_30 IS NOT NULL
    AND d.payment_count >= 3
    AND (d.staff_count >= 2 OR d.store_count >= 2)
    AND d.daily_sum > 2.0 * d.avg_prev_30
    AND d.daily_sum > cp.p95_daily_sum
)
SELECT
  first_name,
  last_name,
  country,
  city,
  payment_date,
  payment_count,
  ROUND(daily_sum, 2) AS daily_sum,
  staff_count,
  store_count,
  ROUND(deviation_from_avg, 2) AS deviation_from_avg,
  DENSE_RANK() OVER (
    PARTITION BY country_id, payment_date
    ORDER BY daily_sum DESC
  ) AS suspicion_rank
FROM (
  SELECT
    s.*,
    s.country_id AS country_id
  FROM suspicious AS s
)
ORDER BY
  country,
  payment_date,
  daily_sum DESC,
  first_name,
  last_name;