WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name
  FROM cus AS c
),
pay_daily AS (
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
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN sto AS s
    ON s.j01 = i.n03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_avg AS (
  SELECT
    pd.*,
    (
      SELECT AVG(CAST(pd2.day_sum AS REAL))
      FROM pay_daily AS pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.day_date >= date(pd.day_date, '-30 days')
        AND pd2.day_date < pd.day_date
    ) AS avg_prev_30
  FROM pay_daily AS pd
),
candidate_days AS (
  SELECT
    d.*,
    d.day_sum / NULLIF(d.avg_prev_30, 0) AS exceed_factor
  FROM daily_with_avg AS d
  WHERE d.avg_prev_30 IS NOT NULL
    AND d.avg_prev_30 > 0
    AND d.payment_count >= 3
    AND (d.staff_count >= 2 OR d.store_count >= 2)
    AND d.day_sum >= 3 * d.avg_prev_30
)
SELECT
  cd.customer_id AS h01,
  cg.first_name,
  cg.last_name,
  cd.day_date AS suspicious_date,
  cd.payment_count,
  ROUND(cd.day_sum, 2) AS day_sum,
  ROUND(cd.avg_prev_30, 2) AS avg_prev_30_day_sum,
  ROUND(cd.exceed_factor, 3) AS exceed_factor,
  RANK() OVER (
    PARTITION BY cd.customer_id
    ORDER BY cd.day_sum DESC
  ) AS customer_day_rank
FROM candidate_days AS cd
JOIN customer_geo AS cg
  ON cg.customer_id = cd.customer_id
ORDER BY
  cd.customer_id,
  customer_day_rank,
  suspicious_date;