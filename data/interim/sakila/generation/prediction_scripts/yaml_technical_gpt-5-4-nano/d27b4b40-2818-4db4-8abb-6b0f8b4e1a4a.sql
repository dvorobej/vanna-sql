WITH daily_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN sto AS st
    ON st.j01 = s.o07
  WHERE p.p06 >= '2004-12-01'
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_prev_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp2.day_sum)
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.day_date >= date(dp.day_date, '-30 days')
        AND dp2.day_date < dp.day_date
    ) AS avg_prev_30
  FROM daily_pay AS dp
),
suspicious_days AS (
  SELECT
    dwp.*,
    (dwp.day_sum / dwp.avg_prev_30) AS exceed_ratio,
    (dwp.day_sum - dwp.avg_prev_30) AS exceed_amount
  FROM daily_with_prev_avg AS dwp
  WHERE dwp.avg_prev_30 IS NOT NULL
    AND dwp.avg_prev_30 > 0
    AND dwp.payment_count >= 3
    AND dwp.day_sum >= 3 * dwp.avg_prev_30
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
),
ranked_days AS (
  SELECT
    sd.*,
    DENSE_RANK() OVER (
      PARTITION BY sd.customer_id
      ORDER BY sd.day_sum DESC
    ) AS day_rank_for_customer
  FROM suspicious_days AS sd
)
SELECT
  c.h01 AS customer_id,
  c.h03,
  c.h04,
  cn.c02 AS country,
  ct.d02 AS city,
  dp.day_date AS suspicious_day,
  dp.payment_count,
  ROUND(dp.day_sum, 2) AS day_sum,
  ROUND(dp.avg_prev_30, 2) AS avg_prev_30_day_sum,
  ROUND(dp.exceed_ratio, 4) AS exceed_ratio,
  dp.day_rank_for_customer
FROM ranked_days AS dp
JOIN cus AS c
  ON c.h01 = dp.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS ct
  ON ct.d01 = a.e05
JOIN cnt AS cn
  ON cn.c01 = ct.d03
ORDER BY
  c.h01,
  dp.day_rank_for_customer,
  dp.day_date;