SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  DATE(p.p06) AS payment_date,
  COUNT(p.p01) AS daily_payment_count,
  SUM(p.p05) AS daily_total_amount,
  MAX(p.p05) AS max_daily_payment,
  CASE
    WHEN COUNT(p.p01) >= 3 OR SUM(p.p05) > 20 THEN 'подозрительная'
    ELSE 'обычная'
  END AS activity_status
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  DATE(p.p06)
ORDER BY
  payment_date,
  daily_total_amount DESC;