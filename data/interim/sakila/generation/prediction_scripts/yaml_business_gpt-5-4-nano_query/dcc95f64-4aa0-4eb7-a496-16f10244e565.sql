SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count_over_5,
  ROUND(SUM(p.p05), 2) AS total_amount_over_5,
  ROUND(AVG(p.p05), 2) AS average_payment_over_5
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE
  p.p06 >= '2005-06-01'
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
  total_amount_over_5 DESC,
  payment_count_over_5 DESC,
  customer_id,
  staff_id;