WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ct.d02 AS city_name,
    cnt.c02 AS country_name,
    cnt.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
),
day_pay AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    MIN(p.p06) AS first_payment_ts,
    MAX(p.p06) AS last_payment_ts,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    cg.customer_name
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN customer_geo AS cg
    ON cg.customer_id = p.p02
  WHERE p.p02 IS NOT NULL
  GROUP BY
    p.p02,
    DATE(p.p06),
    cg.country_id,
    cg.country_name,
    cg.city_name,
    cg.customer_name
),
day_with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(prev.day_amount)
      FROM day_pay AS prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.payment_date >= date(dp.payment_date, '-30 days')
        AND prev.payment_date < dp.payment_date
    ) AS avg_prev_30d_amount
  FROM day_pay AS dp
),
country_daily_ranked AS (
  SELECT
    dp.country_id,
    dp.payment_date,
    dp.day_amount,
    ROW_NUMBER() OVER (
      PARTITION BY dp.country_id, dp.payment_date
      ORDER BY dp.day_amount DESC
    ) AS rn_dummy,
    ROW_NUMBER() OVER (
      PARTITION BY dp.country_id
      ORDER BY dp.day_amount
    ) AS asc_rn,
    COUNT(*) OVER (
      PARTITION BY dp.country_id
    ) AS cnt_days
  FROM day_pay AS dp
),
country_p95 AS (
  SELECT
    country_id,
    AVG(day_amount) AS p95_day_amount
  FROM (
    SELECT
      country_id,
      day_amount,
      asc_rn,
      cnt_days,
      CAST( (0.95 * (cnt_days - 1) + 1) AS INTEGER ) AS p95_index
    FROM country_daily_ranked
  ) AS t
  WHERE asc_rn = p95_index
  GROUP BY country_id
),
flagged AS (
  SELECT
    dwh.*,
    cp.p95_day_amount,
    (dwh.day_amount - dwh.avg_prev_30d_amount) AS deviation_from_avg,
    CASE
      WHEN dwh.avg_prev_30d_amount > 0 THEN dwh.day_amount / dwh.avg_prev_30d_amount
      ELSE NULL
    END AS exceed_multiplier
  FROM day_with_history AS dwh
  JOIN customer_geo AS cg
    ON cg.customer_id = dwh.customer_id
  JOIN country_p95 AS cp
    ON cp.country_id = dwh.country_id
  WHERE cg.customer_id IS NOT NULL
    AND dwh.avg_prev_30d_amount IS NOT NULL
    AND dwh.avg_prev_30d_amount > 0
    AND dwh.payment_count >= 3
    AND dwh.staff_count >= 2
    AND dwh.day_amount > 0.0
    AND dwh.day_amount > (3 * dwh.avg_prev_30d_amount)
    AND dwh.day_amount > cp.p95_day_amount
),
ranked AS (
  SELECT
    f.*,
    RANK() OVER (
      PARTITION BY f.country_id
      ORDER BY (f.day_amount - f.avg_prev_30d_amount) DESC, f.day_amount DESC, f.payment_date
    ) AS suspicious_rank_in_country
  FROM flagged AS f
)
SELECT
  r.customer_id,
  r.customer_name,
  r.city_name,
  r.country_name,
  r.payment_date,
  r.payment_count,
  ROUND(r.day_amount, 2) AS day_amount,
  r.staff_count AS distinct_staff_count,
  r.store_count AS distinct_store_count,
  r.first_payment_ts,
  r.last_payment_ts,
  ROUND(r.max_payment, 2) AS max_payment_for_day,
  ROUND(r.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
  ROUND(r.deviation_from_avg, 2) AS deviation_from_avg,
  r.suspicious_rank_in_country
FROM ranked AS r
ORDER BY
  r.country_name,
  r.suspicious_rank_in_country,
  r.payment_date,
  r.customer_id;