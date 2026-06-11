SELECT
  p.p01 AS payment_id,
  p.p02 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  p.p03 AS staff_id,
  s.o02 || ' ' || s.o03 AS staff_name,
  p.p05 AS amount,
  p.p06 AS payment_date
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
ORDER BY p.p05 DESC
LIMIT 20;