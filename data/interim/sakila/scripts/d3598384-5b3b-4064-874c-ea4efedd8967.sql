SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_transactions,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_amount,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS large_operations,
  CASE
    WHEN SUM(p.p05) > 50.00
      OR SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) >= 3
    THEN 1
    ELSE 0
  END AS suspicious_activity
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING SUM(p.p05) > 50.00
   OR SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) >= 3
ORDER BY
  suspicious_activity DESC,
  total_amount DESC,
  large_operations DESC;