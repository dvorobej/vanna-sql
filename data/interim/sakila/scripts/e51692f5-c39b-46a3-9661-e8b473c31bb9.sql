SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  date(p.p06) AS payment_date,
  COUNT(*) AS payment_count,
  SUM(p.p05) AS total_amount,
  MAX(p.p05) AS max_daily_payment,
  CASE
    WHEN COUNT(*) >= 3 OR SUM(p.p05) > 20 THEN 1
    ELSE 0
  END AS suspicious_activity
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  date(p.p06)
HAVING COUNT(*) >= 3
    OR SUM(p.p05) > 20
ORDER BY
  payment_date,
  total_amount DESC,
  payment_count DESC,
  last_name,
  first_name;