WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h06 AS customer_address_id,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    cty.c01 AS country_id,
    cty.c02 AS country_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cty ON cty.c01 = ct.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  LEFT JOIN stf s ON s.o01 = p.p03
  JOIN customer_geo cg ON cg.customer_id = p.p02
  GROUP BY
    p.p02,
    date(p.p06)
),
pay_daily_with_prev AS (
  SELECT
    pd.*,
    (
      SELECT AVG(pd2.daily_sum)
      FROM pay_daily pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.pay_date >= date(pd.pay_date, '-30 days')
        AND pd2.pay_date < pd.pay_date
    ) AS avg_prev_30d
  FROM pay_daily pd
),
filtered AS (
  SELECT
    *,
    CASE
      WHEN avg_prev_30d IS NULL OR avg_prev_30d = 0 THEN NULL
      ELSE daily_sum / avg_prev_30d
    END AS exceed_ratio
  FROM pay_daily_with_prev
  WHERE avg_prev_30d IS NOT NULL
    AND avg_prev_30d > 0
    AND payment_count >= 3
    AND daily_sum >= 3 * avg_prev_30d
    AND (staff_count >= 2 OR store_count >= 2)
)
SELECT
  f.customer_id,
  cg.country_id,
  cg.country_name,
  cg.city_name,
  f.pay_date,
  f.payment_count,
  ROUND(f.daily_sum, 2) AS daily_sum,
  ROUND(f.avg_prev_30d, 2) AS avg_prev_30d,
  ROUND(f.daily_sum - f.avg_prev_30d, 2) AS deviation_from_avg_prev_30d,
  ROUND(f.exceed_ratio, 3) AS exceed_ratio,
  DENSE_RANK() OVER (
    PARTITION BY f.customer_id
    ORDER BY f.daily_sum DESC
  ) AS customer_day_rank
FROM filtered f
JOIN customer_geo cg ON cg.customer_id = f.customer_id
ORDER BY
  f.customer_id,
  customer_day_rank,
  f.pay_date;