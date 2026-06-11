WITH daily_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    city.d02 AS city_name,
    DATE(p.p06) AS suspicious_date,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = city.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    c.h01, c.h03, c.h04, cnt.c02, city.d02, DATE(p.p06)
),
daily_with_history AS (
  SELECT
    dc.*,
    (
      SELECT AVG(dc_prev.day_amount)
      FROM daily_customer AS dc_prev
      WHERE dc_prev.customer_id = dc.customer_id
        AND dc_prev.suspicious_date >= DATE(dc.suspicious_date, '-30 days')
        AND dc_prev.suspicious_date < dc.suspicious_date
    ) AS avg_prev_30d_day_amount
  FROM daily_customer AS dc
),
flagged AS (
  SELECT
    dwh.*,
    (dwh.day_amount / NULLIF(dwh.avg_prev_30d_day_amount, 0)) AS exceed_ratio
  FROM daily_with_history AS dwh
  WHERE dwh.avg_prev_30d_day_amount IS NOT NULL
    AND dwh.day_amount >= 3.0 * dwh.avg_prev_30d_day_amount
    AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name,
  city_name,
  suspicious_date AS suspicious_activity_date,
  day_amount AS daily_payment_amount,
  payment_count,
  staff_count AS distinct_staff_count,
  avg_prev_30d_day_amount AS avg_daily_amount_prev_30_days,
  RANK() OVER (
    ORDER BY (day_amount - avg_prev_30d_day_amount) DESC, day_amount DESC, customer_id
  ) AS suspicion_rank_among_all
FROM flagged
ORDER BY
  suspicion_rank_among_all,
  daily_payment_amount DESC,
  customer_id,
  suspicious_activity_date;