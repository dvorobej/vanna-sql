WITH daily_base AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    MIN(p.p06) AS min_payment_time,
    MAX(p.p06) AS max_payment_time
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    DATE(p.p06)
),
daily_with_customer_history AS (
  SELECT
    db.*,
    (
      SELECT AVG(db_prev.day_amount)
      FROM daily_base AS db_prev
      WHERE db_prev.customer_id = db.customer_id
        AND db_prev.payment_day >= DATE(db.payment_day, '-30 days')
        AND db_prev.payment_day < db.payment_day
    ) AS avg_prev_30d_amount
  FROM daily_base AS db
),
daily_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  WHERE c.h07 = 'Y'
),
daily_with_country_percentile AS (
  SELECT
    dh.customer_id,
    dh.payment_day,
    dh.payment_count,
    dh.day_amount,
    dh.staff_count,
    dh.store_count,
    dh.min_payment_time,
    dh.max_payment_time,
    dh.avg_prev_30d_amount,
    (
      SELECT MAX(x.day_amount)
      FROM (
        SELECT
          db2.day_amount,
          NTILE(100) OVER (PARTITION BY dbg.country_name ORDER BY db2.day_amount) AS nt
        FROM daily_with_customer_history AS db2
        JOIN daily_geo AS dbg
          ON dbg.customer_id = db2.customer_id
      ) AS x
      WHERE x.nt >= 95
    ) AS p95_country_day_amount
  FROM daily_with_customer_history AS dh
  JOIN daily_geo AS dbg2
    ON dbg2.customer_id = dh.customer_id
  LEFT JOIN daily_geo AS dgc
    ON dgc.customer_id = dh.customer_id
  LIMIT 1
),
filtered_candidates AS (
  SELECT
    dh.customer_id,
    dg.city_name,
    dg.country_name,
    dh.payment_day AS payment_date,
    dh.payment_count,
    dh.day_amount AS total_amount,
    dh.staff_count,
    dh.store_count,
    dh.min_payment_time,
    dh.max_payment_time,
    (
      SELECT MAX(CAST(p2.p05 AS REAL))
      FROM pay AS p2
      WHERE p2.p02 = dh.customer_id
        AND DATE(p2.p06) = dh.payment_day
    ) AS max_payment_amount,
    dh.avg_prev_30d_amount,
    (
      SELECT
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY db2.day_amount)
      FROM daily_with_customer_history AS db2
      JOIN daily_geo AS dbg
        ON dbg.customer_id = db2.customer_id
      WHERE dbg.country_name = dg.country_name
    ) AS p95_country_day_amount
  FROM daily_with_customer_history AS dh
  JOIN daily_geo AS dg
    ON dg.customer_id = dh.customer_id
  WHERE dh.payment_count >= 3
    AND dh.staff_count >= 2
    AND dh.avg_prev_30d_amount IS NOT NULL
    AND dh.avg_prev_30d_amount > 0
    AND dh.day_amount > 3.0 * dh.avg_prev_30d_amount
    AND dh.day_amount > (
      SELECT
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY db2.day_amount)
      FROM daily_with_customer_history AS db2
      JOIN daily_geo AS dbg
        ON dbg.customer_id = db2.customer_id
      WHERE dbg.country_name = dg.country_name
    )
),
ranked AS (
  SELECT
    fc.*,
    RANK() OVER (
      PARTITION BY fc.country_name
      ORDER BY fc.day_amount / NULLIF(fc.avg_prev_30d_amount, 0) DESC,
               fc.total_amount DESC,
               fc.customer_id
    ) AS suspicion_rank_in_country
  FROM filtered_candidates AS fc
)
SELECT
  customer_id AS h01,
  city_name AS d02,
  country_name AS c02,
  payment_date AS p06,
  payment_count,
  ROUND(total_amount, 2) AS total_amount,
  staff_count AS employees_count,
  store_count AS stores_count,
  min_payment_time AS min_payment_time_in_day,
  max_payment_time AS max_payment_time_in_day,
  ROUND(max_payment_amount, 2) AS max_payment_amount,
  suspicion_rank_in_country
FROM ranked
ORDER BY
  c02,
  suspicion_rank_in_country,
  payment_date,
  h01;