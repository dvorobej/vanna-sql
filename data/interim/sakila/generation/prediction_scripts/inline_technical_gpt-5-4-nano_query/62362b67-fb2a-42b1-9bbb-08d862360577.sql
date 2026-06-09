WITH daily_customer AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS day_amount
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  GROUP BY
    p.p02,
    c.h03,
    c.h04,
    cnt.c02,
    cty.d02,
    date(p.p06)
),
daily_customer_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
with_history AS (
  SELECT
    dc.*,
    dss.distinct_staff_count,
    dss.distinct_store_count,
    (
      SELECT AVG(dc_prev.day_amount)
      FROM daily_customer AS dc_prev
      WHERE dc_prev.customer_id = dc.customer_id
        AND dc_prev.payment_date >= date(dc.payment_date, '-30 day')
        AND dc_prev.payment_date < dc.payment_date
    ) AS avg_prev_30d_day_amount
  FROM daily_customer AS dc
  JOIN daily_customer_staff_store AS dss
    ON dss.customer_id = dc.customer_id
   AND dss.payment_date = dc.payment_date
),
suspicious_days AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    country_name,
    city_name,
    payment_date,
    payment_count,
    day_amount,
    distinct_staff_count,
    distinct_store_count,
    avg_prev_30d_day_amount,
    (day_amount / avg_prev_30d_day_amount) AS exceed_ratio
  FROM with_history
  WHERE avg_prev_30d_day_amount IS NOT NULL
    AND avg_prev_30d_day_amount > 0
    AND day_amount >= 3.0 * avg_prev_30d_day_amount
    AND (distinct_staff_count > 1 OR distinct_store_count > 1)
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name,
  city_name,
  payment_date AS suspicious_date,
  ROUND(day_amount, 2) AS day_amount,
  payment_count,
  distinct_staff_count AS staff_count,
  ROUND(avg_prev_30d_day_amount, 2) AS avg_prev_30d_day_amount,
  RANK() OVER (
    ORDER BY exceed_ratio DESC, day_amount DESC, customer_id
  ) AS suspicion_rank_by_exceedance
FROM suspicious_days
ORDER BY suspicion_rank_by_exceedance, suspicious_date, customer_id;