WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp_prev.day_amount)
      FROM daily_payments AS dp_prev
      WHERE dp_prev.customer_id = dp.customer_id
        AND dp_prev.payment_date >= date(dp.payment_date, '-30 day')
        AND dp_prev.payment_date < dp.payment_date
    ) AS avg_prev_30d
  FROM daily_payments AS dp
),
suspicious_days AS (
  SELECT
    dwa.*,
    CASE
      WHEN dwa.avg_prev_30d IS NULL OR dwa.avg_prev_30d = 0 THEN NULL
      ELSE dwa.day_amount / dwa.avg_prev_30d
    END AS suspicious_ratio
  FROM daily_with_avg AS dwa
  WHERE dwa.avg_prev_30d IS NOT NULL
    AND dwa.avg_prev_30d > 0
    AND dwa.day_amount >= 3.0 * dwa.avg_prev_30d
)
SELECT
  sd.customer_id,
  cg.first_name,
  cg.last_name,
  cg.country_name AS country,
  cg.city_name AS city,
  sd.payment_date AS payment_day,
  ROUND(sd.day_amount, 2) AS day_amount,
  sd.payment_count,
  sd.staff_count,
  sd.store_count,
  ROUND(sd.avg_prev_30d, 2) AS avg_daily_prev_30d,
  ROUND(sd.suspicious_ratio, 2) AS suspicion_ratio,
  RANK() OVER (
    PARTITION BY sd.customer_id
    ORDER BY sd.suspicious_ratio DESC, sd.day_amount DESC, sd.payment_date
  ) AS suspicion_rank
FROM suspicious_days AS sd
JOIN customer_geo AS cg
  ON cg.customer_id = sd.customer_id
ORDER BY
  cg.country_name,
  cg.city_name,
  sd.customer_id,
  suspicion_rank,
  sd.payment_date;