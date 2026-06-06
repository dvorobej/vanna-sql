WITH RECURSIVE
bounds AS (
  SELECT
    date(MIN(p06)) AS min_date,
    date(MAX(p06)) AS max_date
  FROM pay
),
calendar(window_start) AS (
  SELECT min_date
  FROM bounds
  WHERE min_date IS NOT NULL

  UNION ALL

  SELECT date(window_start, '+1 day')
  FROM calendar
  CROSS JOIN bounds
  WHERE window_start < max_date
),
customer_dim AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    city.d02 AS city_name,
    country.c01 AS country_id,
    country.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS country
    ON country.c01 = city.d03
),
raw_payments AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.o07 AS store_id
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
),
customer_windows AS (
  SELECT
    cd.customer_id,
    cd.customer_name,
    cd.city_name,
    cd.country_id,
    cd.country_name,
    cal.window_start,
    date(cal.window_start, '+6 day') AS window_end
  FROM customer_dim AS cd
  CROSS JOIN calendar AS cal
),
window_metrics AS (
  SELECT
    cw.customer_id,
    cw.customer_name,
    cw.city_name,
    cw.country_id,
    cw.country_name,
    cw.window_start,
    cw.window_end,
    COALESCE(SUM(
      CASE
        WHEN rp.payment_day >= cw.window_start
         AND rp.payment_day < date(cw.window_start, '+7 day')
        THEN rp.amount
        ELSE 0
      END
    ), 0.0) AS window_payment_sum,
    COUNT(
      CASE
        WHEN rp.payment_day >= cw.window_start
         AND rp.payment_day < date(cw.window_start, '+7 day')
        THEN rp.payment_id
      END
    ) AS window_payment_count,
    COUNT(DISTINCT
      CASE
        WHEN rp.payment_day >= cw.window_start
         AND rp.payment_day < date(cw.window_start, '+7 day')
        THEN rp.staff_id
      END
    ) AS staff_count,
    COUNT(DISTINCT
      CASE
        WHEN rp.payment_day >= cw.window_start
         AND rp.payment_day < date(cw.window_start, '+7 day')
        THEN rp.store_id
      END
    ) AS store_count,
    COALESCE(SUM(
      CASE
        WHEN rp.payment_day >= date(cw.window_start, '-30 day')
         AND rp.payment_day < cw.window_start
        THEN rp.amount
        ELSE 0
      END
    ), 0.0) * 7.0 / 30.0 AS normal_7d_payment_sum,
    COUNT(
      CASE
        WHEN rp.payment_day >= date(cw.window_start, '-30 day')
         AND rp.payment_day < cw.window_start
        THEN rp.payment_id
      END
    ) * 7.0 / 30.0 AS normal_7d_payment_count
  FROM customer_windows AS cw
  LEFT JOIN raw_payments AS rp
    ON rp.customer_id = cw.customer_id
   AND rp.payment_day >= date(cw.window_start, '-30 day')
   AND rp.payment_day < date(cw.window_start, '+7 day')
  GROUP BY
    cw.customer_id,
    cw.customer_name,
    cw.city_name,
    cw.country_id,
    cw.country_name,
    cw.window_start,
    cw.window_end
),
country_ranked AS (
  SELECT
    wm.*,
    ROW_NUMBER() OVER (
      PARTITION BY wm.country_id, wm.window_start
      ORDER BY wm.window_payment_sum
    ) AS country_sum_asc_rank,
    RANK() OVER (
      PARTITION BY wm.country_id, wm.window_start
      ORDER BY wm.window_payment_sum DESC
    ) AS country_sum_desc_rank,
    COUNT(*) OVER (
      PARTITION BY wm.country_id, wm.window_start
    ) AS country_customer_count
  FROM window_metrics AS wm
),
country_p95 AS (
  SELECT
    country_id,
    window_start,
    MAX(
      CASE
        WHEN country_sum_asc_rank = CAST((country_customer_count * 95 + 99) / 100 AS INTEGER)
        THEN window_payment_sum
      END
    ) AS country_95_percentile_sum
  FROM country_ranked
  GROUP BY
    country_id,
    window_start
),
scored AS (
  SELECT
    cr.customer_id,
    cr.customer_name,
    cr.country_name,
    cr.city_name,
    cr.window_start,
    cr.window_end,
    cr.window_payment_sum,
    cr.window_payment_count,
    cr.normal_7d_payment_sum,
    cr.normal_7d_payment_count,
    cr.staff_count,
    cr.store_count,
    cr.country_sum_desc_rank,
    cr.country_customer_count,
    cp.country_95_percentile_sum,
    cr.window_payment_sum / NULLIF(cr.normal_7d_payment_sum, 0) AS amount_to_normal_ratio,
    cr.window_payment_count / NULLIF(cr.normal_7d_payment_count, 0) AS count_to_normal_ratio,
    cr.window_payment_sum / NULLIF(cp.country_95_percentile_sum, 0) AS amount_to_country_p95_ratio,
    (
      cr.window_payment_sum / NULLIF(cr.normal_7d_payment_sum, 0)
      + cr.window_payment_count / NULLIF(cr.normal_7d_payment_count, 0)
      + cr.window_payment_sum / NULLIF(cp.country_95_percentile_sum, 0)
      + cr.staff_count * 0.25
      + cr.store_count * 0.50
    ) AS suspicious_score
  FROM country_ranked AS cr
  JOIN country_p95 AS cp
    ON cp.country_id = cr.country_id
   AND cp.window_start = cr.window_start
  WHERE cr.window_payment_count > 0
    AND cr.normal_7d_payment_sum > 0
    AND cr.normal_7d_payment_count > 0
    AND cp.country_95_percentile_sum > 0
    AND cr.window_payment_sum >= cr.normal_7d_payment_sum * 3.0
    AND cr.window_payment_sum >= cp.country_95_percentile_sum
)
SELECT
  RANK() OVER (
    ORDER BY suspicious_score DESC, window_payment_sum DESC, window_payment_count DESC
  ) AS suspicious_rank,
  customer_id,
  customer_name,
  country_name,
  city_name,
  window_start,
  window_end,
  ROUND(window_payment_sum, 2) AS window_payment_sum,
  window_payment_count,
  staff_count,
  store_count,
  ROUND(normal_7d_payment_sum, 2) AS normal_7d_payment_sum,
  ROUND(normal_7d_payment_count, 2) AS normal_7d_payment_count,
  ROUND(country_95_percentile_sum, 2) AS country_95_percentile_sum,
  country_sum_desc_rank,
  country_customer_count,
  ROUND(amount_to_normal_ratio, 2) AS amount_to_normal_ratio,
  ROUND(count_to_normal_ratio, 2) AS count_to_normal_ratio,
  ROUND(amount_to_country_p95_ratio, 2) AS amount_to_country_p95_ratio,
  ROUND(suspicious_score, 2) AS suspicious_score
FROM scored
ORDER BY
  suspicious_rank,
  window_start,
  country_name,
  customer_id;