SELECT
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 30 THEN 'повышенное внимание'
    ELSE 'обычный'
  END AS attention_flag
FROM cus AS c
JOIN pay AS p
  ON c.h01 = p.p02
JOIN stf AS s
  ON p.p03 = s.o01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING COUNT(p.p01) >= 5;