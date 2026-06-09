WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country_name,
    cnt.c01 AS country_id,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
daily AS (
  SELECT
    p.p02 AS customer_id,
    cg.customer_name,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    date(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN customer_geo AS cg ON cg.customer_id = p.p02
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    cg.customer_name,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_sum)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 days')
        AND d2.day_date < d.day_date
    ) AS avg_prev_30d
  FROM daily AS d
),
country_daily_ranked AS (
  SELECT
    dd.country_id,
    dd.day_sum,
    ROW_NUMBER() OVER (PARTITION BY dd.country_id ORDER BY dd.day_sum) AS rn,
    COUNT(*) OVER (PARTITION BY dd.country_id) AS cnt
  FROM daily_with_history AS dd
),
country_p95 AS (
  SELECT
    country_id,
    MIN(day_sum) AS p95_day_sum
  FROM country_daily_ranked
  WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
  GROUP BY country_id
),
suspicious AS (
  SELECT
    dwh.customer_name,
    dwh.country_name,
    dwh.city_name,
    dwh.day_date,
    dwh.payment_count,
    ROUND(dwh.day_sum, 2) AS day_sum,
    dwh.staff_count,
    (dwh.day_sum - dwh.avg_prev_30d) AS deviation_from_avg_prev_30d,
    (dwh.day_sum / NULLIF(dwh.avg_prev_30d, 0.0)) AS ratio_vs_avg_prev_30d,
    cp.p95_day_sum,
    RANK() OVER (
      PARTITION BY dwh.country_id
      ORDER BY dwh.day_sum - dwh.avg_prev_30d DESC
    ) AS suspicion_rank
  FROM daily_with_history AS dwh
  JOIN country_p95 AS cp
    ON cp.country_id = dwh.country_id
  WHERE dwh.payment_count >= 3
    AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
    AND dwh.avg_prev_30d IS NOT NULL
    AND dwh.avg_prev_30d > 0
    AND dwh.day_sum > 2.0 * dwh.avg_prev_30d
    AND dwh.day_sum > cp.p95_day_sum
)
SELECT
  customer_name AS customer,
  country_name AS country,
  city_name AS city,
  day_date AS payment_date,
  payment_count,
  day_sum,
  staff_count,
  ROUND(deviation_from_avg_prev_30d, 2) AS deviation_from_avg_prev_30d,
  suspicion_rank
FROM suspicious
ORDER BY
  country,
  suspicion_rank,
  payment_date,
  customer;