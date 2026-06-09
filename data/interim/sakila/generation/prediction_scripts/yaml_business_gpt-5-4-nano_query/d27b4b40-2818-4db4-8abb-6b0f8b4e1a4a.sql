WITH daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_total_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s0.j01) AS store_count
  FROM pay AS p
  JOIN stf AS st
    ON st.o01 = p.p03
  JOIN sto AS s0
    ON s0.j01 = st.o07
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_avg AS (
  SELECT
    d.customer_id,
    d.payment_date,
    d.day_total_amount,
    d.payment_count,
    d.staff_count,
    d.store_count,
    (
      SELECT AVG(d2.day_total_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_prev_30_day_amount
  FROM daily AS d
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
suspicious_days AS (
  SELECT
    dwa.*,
    (dwa.day_total_amount / NULLIF(dwa.avg_prev_30_day_amount, 0)) AS exceed_ratio
  FROM daily_with_avg AS dwa
  WHERE dwa.avg_prev_30_day_amount IS NOT NULL
    AND dwa.avg_prev_30_day_amount > 0
    AND dwa.day_total_amount >= 3.0 * dwa.avg_prev_30_day_amount
    AND dwa.payment_count >= 3
    AND (dwa.staff_count >= 2 OR dwa.store_count >= 2)
),
ranked AS (
  SELECT
    sd.*,
    RANK() OVER (
      PARTITION BY sd.customer_id
      ORDER BY sd.day_total_amount DESC, sd.payment_date DESC
    ) AS day_suspicious_rank_within_customer
  FROM suspicious_days AS sd
)
SELECT
  r.customer_id,
  cg.country,
  cg.city,
  r.payment_date,
  r.payment_count,
  ROUND(r.day_total_amount, 2) AS total_amount,
  ROUND(r.avg_prev_30_day_amount, 2) AS avg_prev_30_day_amount,
  ROUND(r.exceed_ratio, 4) AS exceed_ratio,
  r.day_suspicious_rank_within_customer
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
  r.customer_id,
  r.day_suspicious_rank_within_customer,
  r.payment_date;