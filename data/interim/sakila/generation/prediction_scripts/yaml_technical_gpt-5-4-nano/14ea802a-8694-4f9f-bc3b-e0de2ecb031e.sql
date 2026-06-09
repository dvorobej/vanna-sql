SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN COUNT(p.p01) > 10 OR SUM(p.p05) > 80 THEN 1
    ELSE 0
  END AS suspicious_activity_flag
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h03,
  c.h04
ORDER BY
  suspicious_activity_flag DESC,
  total_amount DESC,
  average_payment DESC,
  first_name,
  last_name;