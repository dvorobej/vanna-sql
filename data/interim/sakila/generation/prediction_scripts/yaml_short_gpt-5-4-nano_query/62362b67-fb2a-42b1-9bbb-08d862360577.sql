WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
daily_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    SUM(p.p05) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    d.*,
    (
      SELECT AVG(prev.day_amount)
      FROM daily_pay AS prev
      WHERE prev.customer_id = d.customer_id
        AND prev.payment_day >= date(d.payment_day, '-30 day')
        AND prev.payment_day < d.payment_day
    ) AS avg_prev_30d
  FROM daily_pay AS d
),
suspicious_days AS (
  SELECT
    dwh.customer_id,
    dwh.payment_day,
    dwh.day_amount,
    dwh.payment_count,
    dwh.staff_count,
    dwh.store_count,
    dwh.avg_prev_30d,
    (dwh.day_amount / dwh.avg_prev_30d) AS spike_ratio
  FROM daily_with_history AS dwh
  WHERE dwh.avg_prev_30d IS NOT NULL
    AND dwh.avg_prev_30d > 0
    AND dwh.day_amount >= 3.0 * dwh.avg_prev_30d
    AND (dwh.staff_count > 1 OR dwh.store_count > 1)
)
SELECT
  sd.customer_id,
  cg.country_name,
  cg.city_name,
  sd.payment_day AS suspicious_date,
  ROUND(sd.day_amount, 2) AS day_amount,
  sd.payment_count,
  sd.staff_count AS distinct_staff_count,
  ROUND(sd.avg_prev_30d, 2) AS avg_daily_amount_prev_30_days,
  RANK() OVER (
    ORDER BY (sd.day_amount / sd.avg_prev_30d) DESC
  ) AS suspicion_rank
FROM suspicious_days AS sd
JOIN cus AS c ON c.h01 = sd.customer_id
JOIN customer_geo AS cg ON cg.customer_id = sd.customer_id
ORDER BY
  suspicion_rank,
  sd.payment_day,
  sd.customer_id;