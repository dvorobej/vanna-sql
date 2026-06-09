WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    ct.d02 AS city,
    cnt.c01 AS country_id
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt ON cnt.c01 = ct.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    cg.country_id,
    cg.country,
    cg.city,
    date(p.p06) AS payment_date,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    MAX(CASE WHEN p.p04 IS NOT NULL THEN 1 ELSE 0 END) AS has_rental_store
  FROM pay p
  JOIN customer_geo cg ON cg.customer_id = p.p02
  JOIN stf s ON s.o01 = p.p03
  WHERE p.p06 >= '2004-12-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    cg.country_id,
    cg.country,
    cg.city,
    date(p.p06)
),
daily_with_prev_avg AS (
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
  SELECT
    country_id,
    payment_date,
    day_amount AS daily_sum,
    PERCENT_RANK() OVER (PARTITION BY country_id, payment_date ORDER BY day_amount) AS pr
  FROM pay_daily
),
country_p95_threshold AS (
  SELECT
    country_id,
    payment_date,
    MIN(daily_sum) AS p95_daily_amount
  FROM (
    SELECT
      country_id,
      payment_date,
      day_amount AS daily_sum,
      ROW_NUMBER() OVER (
        PARTITION BY country_id, payment_date
        ORDER BY day_amount DESC
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY country_id, payment_date
      ) AS cnt
    FROM pay_daily
  ) x
  WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
  GROUP BY country_id, payment_date
),
suspicious AS (
  SELECT
    dwp.customer_id,
    dwp.customer_name,
    dwp.country,
    dwp.city,
    dwp.payment_date,
    dwp.payment_count,
    dwp.day_amount,
    dwp.staff_count,
    dwp.store_count,
    dwp.avg_prev_30d,
    (dwp.day_amount - dwp.avg_prev_30d) AS deviation_from_avg_prev_30d,
    cpt.p95_daily_amount,
    ROW_NUMBER() OVER (
      PARTITION BY dwp.country_id, dwp.payment_date
      ORDER BY (dwp.day_amount - dwp.avg_prev_30d) DESC
    ) AS rn_in_country_day
  FROM (
    SELECT
      dwp.customer_id,
      cg.customer_name,
      cg.country_id,
      dwp.country,
      dwp.city,
      dwp.payment_date,
      dwp.payment_count,
      dwp.day_amount,
      dwp.staff_count,
      dwp.store_count,
      dwp.avg_prev_30d
    FROM daily_with_prev_avg dwp
    JOIN customer_geo cg ON cg.customer_id = dwp.customer_id
    WHERE dwp.avg_prev_30d IS NOT NULL
  ) dwp
  JOIN country_p95_threshold cpt
    ON cpt.country_id = dwp.country_id
   AND cpt.payment_date = dwp.payment_date
  WHERE dwp.payment_count >= 3
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
    AND dwp.day_amount >= 2.0 * dwp.avg_prev_30d
    AND dwp.day_amount > cpt.p95_daily_amount
)
SELECT
  customer_name AS customer,
  country,
  city,
  payment_date,
  payment_count,
  ROUND(day_amount, 2) AS day_amount,
  staff_count,
  store_count,
  ROUND(deviation_from_avg_prev_30d, 2) AS deviation_from_avg_prev_30d,
  rn_in_country_day AS suspicion_rank_in_country_day
FROM suspicious
ORDER BY
  country,
  payment_date,
  suspicion_rank_in_country_day,
  day_amount DESC;