WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ci.d02 AS city_name,
    co.c02 AS country_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
  WHERE c.h07 = 'Y'
),
daily_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    MIN(p.p06) AS first_payment_ts,
    MAX(p.p06) AS last_payment_ts,
    MAX(CAST(p.p05 AS REAL)) AS max_payment_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(s.o07, -1)) AS distinct_store_count
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    DATE(p.p06)
),
daily_with_history AS (
  SELECT
    d.*,
    (
      SELECT AVG(dh.day_amount)
      FROM daily_staff_store dh
      WHERE dh.customer_id = d.customer_id
        AND dh.payment_date >= DATE(d.payment_date, '-30 day')
        AND dh.payment_date < d.payment_date
    ) AS personal_avg_prev_30d
  FROM daily_staff_store d
),
country_p95 AS (
  SELECT
    country_name,
    payment_date,
    day_amount,
    PERCENT_RANK() OVER (
      PARTITION BY country_name, payment_date
      ORDER BY day_amount
    ) AS pr
  FROM (
    SELECT
      cg.country_name,
      d.payment_date,
      d.day_amount
    FROM daily_with_history d
    JOIN customer_geo cg ON cg.customer_id = d.customer_id
    WHERE d.personal_avg_prev_30d IS NOT NULL
  ) x
),
country_p95_value AS (
  SELECT
    country_name,
    payment_date,
    MAX(day_amount) AS p95_day_amount
  FROM (
    SELECT
      cg.country_name,
      d.payment_date,
      d.day_amount,
      ROW_NUMBER() OVER (
        PARTITION BY cg.country_name, d.payment_date
        ORDER BY d.day_amount DESC
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY cg.country_name, d.payment_date
      ) AS cnt
    FROM daily_with_history d
    JOIN customer_geo cg ON cg.customer_id = d.customer_id
    WHERE d.personal_avg_prev_30d IS NOT NULL
  ) t
  WHERE rn <= CAST(CEIL(0.05 * t.cnt) AS INTEGER)
  GROUP BY country_name, payment_date
),
scored AS (
  SELECT
    dwh.customer_id,
    cg.customer_name,
    cg.city_name,
    cg.country_name,
    dwh.payment_date AS suspicious_date,
    dwh.payment_count,
    dwh.day_amount,
    dwh.distinct_staff_count,
    dwh.distinct_store_count,
    dwh.first_payment_ts,
    dwh.last_payment_ts,
    dwh.max_payment_amount,
    dwh.personal_avg_prev_30d,
    (dwh.day_amount / NULLIF(dwh.personal_avg_prev_30d, 0)) AS amount_vs_personal_avg_ratio,
    (dwh.day_amount - dwh.personal_avg_prev_30d) AS amount_minus_personal_avg,
    cp.p95_day_amount,
    (dwh.day_amount - cp.p95_day_amount) AS amount_minus_country_p95
  FROM daily_with_history dwh
  JOIN customer_geo cg ON cg.customer_id = dwh.customer_id
  JOIN country_p95_value cp
    ON cp.country_name = cg.country_name
   AND cp.payment_date = dwh.payment_date
  WHERE dwh.personal_avg_prev_30d IS NOT NULL
    AND dwh.payment_count >= 3
    AND dwh.distinct_staff_count >= 2
    AND dwh.day_amount > 3.0 * dwh.personal_avg_prev_30d
    AND dwh.day_amount > cp.p95_day_amount
),
ranked AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY s.country_name
      ORDER BY s.amount_minus_personal_avg DESC, s.day_amount DESC, s.customer_id
    ) AS suspicion_rank_within_country
  FROM scored s
)
SELECT
  customer_id,
  customer_name,
  city_name,
  country_name,
  suspicious_date AS payment_date,
  payment_count,
  ROUND(day_amount, 2) AS day_payment_amount,
  distinct_staff_count AS staff_count,
  distinct_store_count AS store_count,
  first_payment_ts AS first_operation_ts,
  last_payment_ts AS last_operation_ts,
  ROUND(max_payment_amount, 2) AS max_payment_amount,
  ROUND(personal_avg_prev_30d, 2) AS personal_avg_prev_30d,
  ROUND(amount_vs_personal_avg_ratio, 2) AS amount_vs_personal_avg_ratio,
  suspicion_rank_within_country
FROM ranked
ORDER BY
  country_name,
  suspicion_rank_within_country,
  suspicious_date,
  customer_id;