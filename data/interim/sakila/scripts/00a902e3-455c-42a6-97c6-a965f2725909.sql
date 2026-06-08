SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  s.o01 AS staff_id,
  s.o02 || ' ' || s.o03 AS staff_name,
  COUNT(p.p01) AS transaction_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  CASE
    WHEN AVG(p.p05) > 7.00 THEN 1
    ELSE 0
  END AS risk_flag
FROM pay AS p
JOIN cus AS c ON c.h01 = p.p02
JOIN stf AS s ON s.o01 = p.p03
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING COUNT(p.p01) >= 5
   AND SUM(p.p05) > 30
ORDER BY total_amount DESC, transaction_count DESC;