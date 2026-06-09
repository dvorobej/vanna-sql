WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country,
    cty.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS cty ON cty.d01 = a.e05
  JOIN cnt AS cnt ON cnt.c01 = cty.d03
),
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_prev_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp_prev.day_sum)
      FROM daily_payments AS dp_prev
      WHERE dp_prev.customer_id = dp.customer_id
        AND dp_prev.day_date >= date(dp.day_date, '-30 days')
        AND dp_prev.day_date < dp.day_date
    ) AS avg_prev_30d
  FROM daily_payments AS dp
),
suspicious_days AS (
  SELECT
    dwp.*,
    (CASE
      WHEN dwp.avg_prev_30d IS NOT NULL AND dwp.avg_prev_30d > 0
      THEN dwp.day_sum / dwp.avg_prev_30d
    END) AS exceed_ratio
  FROM daily_with_prev_avg AS dwp
  WHERE dwp.avg_prev_30d IS NOT NULL
    AND dwp.avg_prev_30d > 0
    AND dwp.day_sum >= 3.0 * dwp.avg_prev_30d
    AND dwp.payment_count >= 3
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
),
ranked_days AS (
  SELECT
    sd.*,
    RANK() OVER (
      PARTITION BY sd.customer_id
      ORDER BY sd.day_sum DESC
    ) AS day_rank_for_customer
  FROM suspicious_days AS sd
)
SELECT
  cg.customer_id,
  cg.first_name,
  cg.last_name,
  cg.country,
  cg.city,
  rd.day_date AS payment_date,
  rd.payment_count,
  ROUND(rd.day_sum, 2) AS total_amount,
  ROUND(rd.avg_prev_30d, 2) AS avg_prev_30d_daily_amount,
  ROUND(rd.exceed_ratio, 2) AS exceed_ratio,
  rd.day_rank_for_customer AS day_rank_by_amount
FROM ranked_days AS rd
JOIN customer_geo AS cg
  ON cg.customer_id = rd.customer_id
ORDER BY
  cg.country,
  cg.city,
  cg.customer_id,
  day_rank_for_customer,
  rd.day_date;