SELECT
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  ROUND(MAX(p.p05), 2) AS max_payment,
  CASE
    WHEN COUNT(p.p01) > 10 OR SUM(p.p05) > 50.00 THEN 1
    ELSE 0
  END AS suspicious_flag
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o02,
  s.o03
ORDER BY
  suspicious_flag DESC,
  total_amount DESC,
  payment_count DESC,
  c.h04,
  c.h03;