SELECT
  c.h01 AS customer_id,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS avg_payment_amount
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
  AND s.o07 <> c.h02
GROUP BY
  c.h01
HAVING SUM(p.p05) > 50.00
ORDER BY
  total_amount DESC,
  payment_count DESC;