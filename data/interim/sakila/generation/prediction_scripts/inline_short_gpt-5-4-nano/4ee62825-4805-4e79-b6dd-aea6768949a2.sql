WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    DATE(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS amount,
    s.o07 AS store_id,
    s.o02 || ' ' || s.o03 AS staff_name
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    ct.city_name,
    cn.country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN (
    SELECT cty.d01 AS city_id, cty.d02 AS city_name, cnt.c01 AS country_id, cnt.c02 AS country_name
    FROM cty
    JOIN cnt ON cnt.c01 = cty.d03
  ) AS ct ON ct.city_id = a.e05
  JOIN cnt AS cn ON cn.c01 = ct.country_id
),
daily_agg AS (
  SELECT
    pe.customer_id,
    cg.city_name,
    cg.country_name,
    pe.payment_day,
    COUNT(pe.payment_id) AS payment_count,
    SUM(pe.amount) AS day_total_amount,
    COUNT(DISTINCT pe.staff_id) AS staff_count,
    COUNT(DISTINCT pe.store_id) AS store_count,
    MIN(pe.payment_id) AS first_payment_id,
    MAX(pe.payment_id) AS last_payment_id,
    MAX(pe.amount) AS max_payment_amount,
    (SELECT MIN(pe2.payment_day)
     FROM payment_enriched AS pe2
     WHERE pe2.customer_id = pe.customer_id
       AND pe2.payment_day = pe.payment_day) AS dummy_min
  FROM payment_enriched AS pe
  JOIN customer_geo AS cg ON cg.customer_id = pe.customer_id
  GROUP BY
    pe.customer_id,
    cg.city_name,
    cg.country_name,
    pe.payment_day
),
daily_first_last AS (
  SELECT
    pe.customer_id,
    DATE(pe.payment_day) AS payment_day,
    (SELECT datetime(MIN(p2.p06)) FROM pay AS p2 WHERE p2.p02 = pe.customer_id AND DATE(p2.p06) = pe.payment_day) AS first_op_time,
    (SELECT datetime(MAX(p2.p06)) FROM pay AS p2 WHERE p2.p02 = pe.customer_id AND DATE(p2.p06) = pe.payment_day) AS last_op_time
  FROM payment_enriched AS pe
  GROUP BY pe.customer_id, DATE(pe.payment_day)
),
customer_avg_30 AS (
  SELECT
    da.customer_id,
    da.payment_day,
    (
      SELECT AVG(da2.day_total_amount)
      FROM daily_agg AS da2
      WHERE da2.customer_id = da.customer_id
        AND da2.payment_day >= date(da.payment_day, '-30 day')
        AND da2.payment_day < da.payment_day
    ) AS customer_hist_avg_30d,
    (
      SELECT MAX(da2.day_total_amount)
      FROM daily_agg AS da2
      WHERE da2.customer_id = da.customer_id
        AND da2.payment_day >= date(da.payment_day, '-30 day')
        AND da2.payment_day < da.payment_day
    ) AS dummy_max
  FROM daily_agg AS da
),
country_ranked_days AS (
  SELECT
    da.country_name,
    da.payment_day,
    da.day_total_amount,
    da.customer_id,
    ROW_NUMBER() OVER (
      PARTITION BY da.country_name
      ORDER BY da.day_total_amount
    ) AS rn_asc,
    COUNT(*) OVER (PARTITION BY da.country_name) AS cnt_days
  FROM daily_agg AS da
),
country_p95 AS (
  SELECT
    country_name,
    day_total_amount AS country_p95_day_amount
  FROM country_ranked_days
  WHERE rn_asc >= CAST((0.95 * (cnt_days - 1) + 1) AS INTEGER)
  ORDER BY country_name
  LIMIT 1
),
suspicious_base AS (
  SELECT
    da.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    da.city_name,
    da.country_name,
    da.payment_day,
    da.payment_count,
    da.day_total_amount,
    da.staff_count,
    da.store_count,
    fl.first_op_time,
    fl.last_op_time,
    da.max_payment_amount,
    ca.customer_hist_avg_30d,
    cp.country_p95_day_amount
  FROM daily_agg AS da
  JOIN cus AS c ON c.h01 = da.customer_id
  LEFT JOIN daily_first_last AS fl
    ON fl.customer_id = da.customer_id
   AND fl.payment_day = da.payment_day
  LEFT JOIN customer_avg_30 AS ca
    ON ca.customer_id = da.customer_id
   AND ca.payment_day = da.payment_day
  LEFT JOIN country_p95 AS cp
    ON cp.country_name = da.country_name
  WHERE da.payment_count >= 3
    AND da.staff_count >= 2
),
ranked AS (
  SELECT
    sb.*,
    DENSE_RANK() OVER (
      PARTITION BY sb.country_name
      ORDER BY sb.day_total_amount DESC
    ) AS suspicion_rank_in_country,
    CASE
      WHEN sb.customer_hist_avg_30d IS NOT NULL AND sb.customer_hist_avg_30d > 0
      THEN sb.day_total_amount / sb.customer_hist_avg_30d
      ELSE NULL
    END AS ratio_vs_customer_avg,
    CASE
      WHEN sb.cptry IS NULL THEN NULL
      ELSE NULL
    END AS dummy
  FROM suspicious_base AS sb
)
SELECT
  r.customer_id,
  r.customer_name,
  r.city_name,
  r.country_name,
  r.payment_day AS date,
  ROUND(r.day_total_amount, 2) AS day_total_amount,
  r.payment_count,
  r.staff_count AS staff_count,
  r.store_count AS store_count,
  r.first_op_time,
  r.last_op_time,
  ROUND(r.max_payment_amount, 2) AS max_payment_amount,
  r.suspicion_rank_in_country AS suspicion_rank
FROM ranked AS r
WHERE
  r.customer_hist_avg_30d IS NOT NULL
  AND r.cptry IS NULL
ORDER BY
  r.country_name,
  r.suspicion_rank_in_country,
  r.payment_day,
  r.customer_id;