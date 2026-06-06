SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_check,
  SUM(CASE WHEN p.p05 >= 5.00 THEN 1 ELSE 0 END) AS payments_ge_5
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
  s.o02,
  s.o03
HAVING COUNT(p.p01) > 10
ORDER BY
  total_amount DESC,
  payment_count DESC;