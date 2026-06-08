SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  s.o01 AS staff_id,
  s.o02 || ' ' || s.o03 AS staff_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_payment_amount,
  ROUND(AVG(p.p05), 2) AS average_payment_amount
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
  AND p.p05 > 5.00
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
ORDER BY
  payment_count DESC,
  total_payment_amount DESC,
  customer_id,
  staff_id;