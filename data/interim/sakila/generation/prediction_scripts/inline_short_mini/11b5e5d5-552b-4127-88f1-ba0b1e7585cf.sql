SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 50 OR AVG(p.p05) > 8 THEN 1
    ELSE 0
  END AS suspicious_activity
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-09-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
ORDER BY
  suspicious_activity DESC,
  total_amount DESC,
  payment_count DESC;