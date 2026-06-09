WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS customer_country,
    cty.d02 AS customer_city,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
daily AS (
  SELECT
    cg.customer_id,
    cg.first_name,
    cg.last_name,
    cg.customer_country,
    cg.customer_city,
    date(p.p06) AS activity_date,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS day_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.p02
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    cg.customer_id,
    cg.first_name,
    cg.last_name,
    cg.customer_country,
    cg.customer_city,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    d.*,
    (
      SELECT AVG(dh.day_amount)
      FROM daily AS dh
      WHERE dh.customer_id = d.customer_id
        AND dh.activity_date >= date(d.activity_date, '-30 day')
        AND dh.activity_date < d.activity_date
    ) AS avg_prev_30d
  FROM daily AS d
),
suspicious AS (
  SELECT
    dwh.*,
    (dwh.day_amount - dwh.avg_prev_30d) AS excess_amount
  FROM daily_with_history AS dwh
  WHERE dwh.avg_prev_30d IS NOT NULL
    AND dwh.avg_prev_30d > 0
    AND dwh.day_amount >= 3.0 * dwh.avg_prev_30d
    AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
)
SELECT
  customer_id,
  first_name,
  last_name,
  customer_country,
  customer_city,
  activity_date AS suspicious_date,
  ROUND(day_amount, 2) AS day_amount,
  payment_count,
  distinct_staff_count AS distinct_staff_or_stores_count,
  ROUND(avg_prev_30d, 2) AS avg_prev_30d,
  RANK() OVER (
    ORDER BY excess_amount DESC, day_amount DESC, customer_id
  ) AS suspicion_rank_overall
FROM suspicious
ORDER BY
  suspicion_rank_overall,
  suspicious_date,
  customer_id;