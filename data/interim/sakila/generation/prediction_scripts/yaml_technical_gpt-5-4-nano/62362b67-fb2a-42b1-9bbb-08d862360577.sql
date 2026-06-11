WITH day_payments AS (
  SELECT
    cus.h01 AS customer_id,
    DATE(p.p06) AS activity_day,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS day_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT sto.j01) AS distinct_store_count
  FROM pay AS p
  JOIN cus
    ON cus.h01 = p.p02
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN sto
    ON sto.j01 = i.n03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    cus.h01,
    DATE(p.p06)
),
day_with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp_prev.day_amount)
      FROM day_payments AS dp_prev
      WHERE dp_prev.customer_id = dp.customer_id
        AND dp_prev.activity_day >= DATE(dp.activity_day, '-30 days')
        AND dp_prev.activity_day < dp.activity_day
    ) AS avg_prev_30d
  FROM day_payments AS dp
),
suspicious_days AS (
  SELECT
    dwh.customer_id,
    dwh.activity_day AS suspicious_date,
    dwh.payment_count,
    dwh.day_amount,
    dwh.distinct_staff_count,
    dwh.distinct_store_count,
    dwh.avg_prev_30d,
    (dwh.day_amount / dwh.avg_prev_30d) AS exceed_ratio
  FROM day_with_history AS dwh
  WHERE dwh.avg_prev_30d IS NOT NULL
    AND dwh.avg_prev_30d > 0
    AND dwh.day_amount >= 3.0 * dwh.avg_prev_30d
    AND (dwh.distinct_staff_count > 1 OR dwh.distinct_store_count > 1)
)
SELECT
  sd.customer_id AS customer_h01,
  c.h03 AS first_name,
  c.h04 AS last_name,
  cnt.c02 AS country_name,
  cty.d02 AS city_name,
  sd.suspicious_date AS suspicious_q02_p06_date,
  ROUND(sd.day_amount, 2) AS day_amount,
  sd.payment_count,
  sd.distinct_staff_count AS staff_count,
  ROUND(sd.avg_prev_30d, 2) AS avg_day_amount_prev_30d,
  RANK() OVER (
    PARTITION BY sd.customer_id
    ORDER BY sd.exceed_ratio DESC
  ) AS customer_day_exceed_rank,
  RANK() OVER (
    ORDER BY sd.exceed_ratio DESC, sd.day_amount DESC, sd.customer_id
  ) AS suspicious_rank_among_customers
FROM suspicious_days AS sd
JOIN cus AS c
  ON c.h01 = sd.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty
  ON cty.d01 = a.e05
JOIN cnt
  ON cnt.c01 = cty.d03
ORDER BY
  exceed_ratio DESC,
  sd.day_amount DESC,
  sd.customer_id;