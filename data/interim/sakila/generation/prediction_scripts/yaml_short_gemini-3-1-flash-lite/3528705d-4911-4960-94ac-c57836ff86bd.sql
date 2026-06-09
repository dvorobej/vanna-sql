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
  ROUND(1.0 * COUNT(p.p01) / SUM(COUNT(p.p01)) OVER (PARTITION BY c.h01), 4) AS staff_share
FROM pay AS p
JOIN cus AS c ON p.p02 = c.h01
JOIN stf AS s ON p.p03 = s.o01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING SUM(p.p05) > 50
ORDER BY
  total_amount DESC,
  customer_id,
  staff_id;