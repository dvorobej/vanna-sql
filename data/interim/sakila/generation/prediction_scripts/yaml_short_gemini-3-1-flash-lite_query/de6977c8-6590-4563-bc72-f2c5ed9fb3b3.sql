SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_check,
  1.0 * SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) / COUNT(p.p01) AS share_large_payments
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON p.p03 = s.o01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING COUNT(p.p01) >= 5
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;