SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_payment_amount,
  AVG(p.p05) AS average_payment_amount,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS payment_count_above_8
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 <= '2005-08-31 23:59:59'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING
  COUNT(p.p01) >= 10
  OR SUM(p.p05) > 100.00
ORDER BY
  customer_id,
  staff_id;