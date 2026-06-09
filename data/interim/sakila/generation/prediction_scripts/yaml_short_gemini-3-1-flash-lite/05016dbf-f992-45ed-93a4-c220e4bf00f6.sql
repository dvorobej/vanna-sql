SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  s.o01 AS staff_id,
  s.o02 || ' ' || s.o03 AS staff_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS count_payments_above_8
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
JOIN stf AS s
  ON p.p03 = s.o01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-09-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING COUNT(p.p01) >= 10
   OR SUM(p.p05) > 100.00
ORDER BY
  total_amount DESC,
  payment_count DESC;