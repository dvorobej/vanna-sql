WITH payment_days AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(st.o07, -1)) AS distinct_store_count
  FROM pay AS p
  LEFT JOIN stf AS st
    ON st.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
with_prev_30 AS (
  SELECT
    pd.*,
    (
      SELECT AVG(CAST(p2day.day_amount AS REAL))
      FROM payment_days AS p2day
      WHERE p2day.customer_id = pd.customer_id
        AND p2day.payment_date >= date(pd.payment_date, '-30 day')
        AND p2day.payment_date < pd.payment_date
    ) AS avg_prev_30_day_amount
  FROM payment_days AS pd
),
suspicious_days AS (
  SELECT
    w.*,
    (w.day_amount / w.avg_prev_30_day_amount) AS exceed_ratio
  FROM with_prev_30 AS w
  WHERE w.avg_prev_30_day_amount IS NOT NULL
    AND w.avg_prev_30_day_amount > 0
    AND w.day_amount >= 3 * w.avg_prev_30_day_amount
    AND w.payment_count >= 3
    AND (w.distinct_staff_count >= 2 OR w.distinct_store_count >= 2)
),
ranked_days AS (
  SELECT
    sd.*,
    RANK() OVER (
      PARTITION BY sd.customer_id
      ORDER BY sd.day_amount DESC
    ) AS day_amount_rank_within_customer
  FROM suspicious_days AS sd
)
SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  cn.c02 AS country,
  ct.d02 AS city,
  rd.payment_date AS activity_date,
  rd.payment_count,
  ROUND(rd.day_amount, 2) AS day_payment_amount,
  ROUND(rd.avg_prev_30_day_amount, 2) AS avg_prev_30_day_amount,
  ROUND(rd.exceed_ratio, 4) AS exceed_ratio,
  rd.day_amount_rank_within_customer AS day_amount_rank
FROM ranked_days AS rd
JOIN cus AS c
  ON c.h01 = rd.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS ct
  ON ct.d01 = a.e05
JOIN cnt AS cn
  ON cn.c01 = ct.d03
ORDER BY
  rd.customer_id,
  rd.day_amount_rank_within_customer,
  rd.payment_date;