SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_amount,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(CASE WHEN p.p03 IS NOT NULL THEN p.p01 END) AS staff_payment_count,
  ROUND(SUM(CASE WHEN p.p03 IS NOT NULL THEN p.p05 ELSE 0 END), 2) AS staff_total_amount
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING SUM(p.p05) > 50.00
ORDER BY
  total_amount DESC,
  staff_total_amount DESC,
  customer_id,
  staff_id;