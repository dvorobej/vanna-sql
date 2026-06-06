WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount,
    p.p06 AS payment_ts,
    date(strftime('%Y-%m-01', p.p06)) AS month_start
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
customer_month AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    p.month_start,
    COUNT(p.payment_id) AS payment_count,
    ROUND(SUM(p.amount), 2) AS total_amount,
    ROUND(AVG(p.amount), 2) AS avg_payment_amount,
    COUNT(DISTINCT p.staff_id) AS staff_count
  FROM payments_2005 AS p
  JOIN cus AS c
    ON c.h01 = p.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cnt.c01,
    cnt.c02,
    p.month_start
),
series_24h AS (
  SELECT DISTINCT
    p1.customer_id,
    p1.month_start
  FROM payments_2005 AS p1
  JOIN payments_2005 AS p2
    ON p2.customer_id = p1.customer_id
   AND p2.month_start = p1.month_start
   AND p2.payment_ts >= p1.payment_ts
   AND p2.payment_ts < datetime(p1.payment_ts, '+24 hours')
  GROUP BY
    p1.customer_id,
    p1.month_start,
    p1.payment_id
  HAVING COUNT(p2.payment_id) >= 3
),
ranked AS (
  SELECT
    cm.*,
    ROUND(AVG(cm.total_amount) OVER (
      PARTITION BY cm.country_id, cm.month_start
    ), 2) AS country_avg_total_amount,
    ROUND(AVG(cm.payment_count * 1.0) OVER (
      PARTITION BY cm.country_id, cm.month_start
    ), 2) AS country_avg_payment_count,
    RANK() OVER (
      PARTITION BY cm.country_id, cm.month_start
      ORDER BY cm.total_amount DESC
    ) AS amount_rank_in_country,
    COUNT(*) OVER (
      PARTITION BY cm.country_id, cm.month_start
    ) AS customer_count_in_country
  FROM customer_month AS cm
)
SELECT
  r.country_name,
  strftime('%Y-%m', r.month_start) AS payment_month,
  r.customer_id,
  r.first_name,
  r.last_name,
  r.payment_count,
  r.total_amount,
  r.avg_payment_amount,
  r.country_avg_total_amount,
  r.country_avg_payment_count,
  r.staff_count,
  r.amount_rank_in_country
FROM ranked AS r
JOIN series_24h AS s
  ON s.customer_id = r.customer_id
 AND s.month_start = r.month_start
WHERE r.amount_rank_in_country <= MAX(1, CAST(r.customer_count_in_country * 0.10 + 0.999999 AS INTEGER))
  AND r.payment_count > r.country_avg_payment_count
  AND r.staff_count >= 2
ORDER BY
  r.country_name,
  r.month_start,
  r.amount_rank_in_country,
  r.total_amount DESC;