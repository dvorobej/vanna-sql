WITH customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 || ' ' || cus.h04 AS customer_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    cg.customer_name,
    cg.country_name,
    cg.city_name,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN customer_geo AS cg ON cg.customer_id = p.p02
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    cg.customer_name,
    cg.country_name,
    cg.city_name,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(CAST(prev.day_sum AS REAL))
      FROM daily_payments AS prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.payment_date >= date(dp.payment_date, '-30 days')
        AND prev.payment_date < dp.payment_date
    ) AS avg_prev_30d
  FROM daily_payments AS dp
),
qualified_days AS (
  SELECT
    dwh.*,
    dwh.day_sum / dwh.avg_prev_30d AS exceed_ratio
  FROM daily_with_history AS dwh
  WHERE dwh.avg_prev_30d IS NOT NULL
    AND dwh.avg_prev_30d > 0
    AND dwh.day_sum >= 3.0 * dwh.avg_prev_30d
    AND dwh.payment_count >= 3
    AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
),
ranked_days AS (
  SELECT
    qd.*,
    RANK() OVER (
      PARTITION BY qd.customer_id
      ORDER BY qd.day_sum DESC
    ) AS day_rank_by_sum_among_customer_days
  FROM qualified_days AS qd
)
SELECT
  customer_name,
  country_name,
  city_name,
  payment_date,
  payment_count,
  ROUND(day_sum, 2) AS day_sum,
  ROUND(avg_prev_30d, 2) AS avg_prev_30d,
  ROUND(exceed_ratio, 2) AS exceed_ratio,
  day_rank_by_sum_among_customer_days
FROM ranked_days
ORDER BY
  country_name,
  day_rank_by_sum_among_customer_days,
  payment_date,
  day_sum DESC,
  customer_name;