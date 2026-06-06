WITH payment_monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    date(strftime('%Y-%m-01', p.p06)) AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS total_amount,
    AVG(p.p05) AS average_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    MAX(p.p05) AS max_payment
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = city.d03
  JOIN pay AS p
    ON p.p02 = c.h01
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
    AND c.h07 IN ('1', 'Y')
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cnt.c02,
    date(strftime('%Y-%m-01', p.p06))
),
payment_ranked AS (
  SELECT
    pm.*,
    AVG(pm.payment_count) OVER (
      PARTITION BY pm.country_name, pm.month_start
    ) AS country_month_avg_payment_count,
    AVG(pm.total_amount) OVER (
      PARTITION BY pm.country_name, pm.month_start
    ) AS country_month_avg_total_amount,
    ROW_NUMBER() OVER (
      PARTITION BY pm.country_name, pm.month_start
      ORDER BY pm.total_amount DESC, pm.payment_count DESC, pm.customer_id
    ) AS country_month_amount_rank,
    COUNT(*) OVER (
      PARTITION BY pm.country_name, pm.month_start
    ) AS country_month_customer_count
  FROM payment_monthly AS pm
),
payment_series AS (
  SELECT DISTINCT
    p1.p02 AS customer_id,
    date(strftime('%Y-%m-01', p1.p06)) AS month_start
  FROM pay AS p1
  WHERE p1.p06 >= '2005-01-01'
    AND p1.p06 < '2006-01-01'
    AND EXISTS (
      SELECT 1
      FROM pay AS p2
      JOIN pay AS p3
        ON p3.p02 = p1.p02
       AND datetime(p3.p06) >= datetime(p2.p06)
       AND datetime(p3.p06) < datetime(p2.p06, '+24 hours')
      WHERE p2.p02 = p1.p02
        AND date(strftime('%Y-%m-01', p2.p06)) = date(strftime('%Y-%m-01', p1.p06))
      GROUP BY p2.p02, p2.p06
      HAVING COUNT(*) >= 3
    )
),
customer_activity AS (
  SELECT
    pr.*,
    CASE
      WHEN pr.payment_count > pr.country_month_avg_payment_count
        AND pr.country_month_amount_rank <= CAST((pr.country_month_customer_count + 9) / 10 AS INTEGER)
        AND pr.staff_count = 2
        AND EXISTS (
          SELECT 1
          FROM payment_series AS ps
          WHERE ps.customer_id = pr.customer_id
            AND ps.month_start = pr.month_start
        )
      THEN 1
      ELSE 0
    END AS suspicious_activity
  FROM payment_ranked AS pr
)
SELECT
  country_name,
  strftime('%Y-%m', month_start) AS payment_month,
  customer_id,
  first_name,
  last_name,
  payment_count,
  ROUND(total_amount, 2) AS total_amount,
  ROUND(average_amount, 2) AS average_amount,
  staff_count,
  max_payment,
  country_month_amount_rank AS amount_rank_in_country,
  suspicious_activity
FROM customer_activity
WHERE suspicious_activity = 1
ORDER BY
  country_name,
  payment_month,
  total_amount DESC,
  payment_count DESC,
  customer_id;