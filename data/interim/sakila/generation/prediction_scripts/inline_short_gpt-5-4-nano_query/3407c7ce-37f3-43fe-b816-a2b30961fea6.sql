SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  MAX(p.p05) AS max_payment,
  COUNT(DISTINCT s.o01) AS staff_count
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE
  c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  COUNT(p.p01) >= 5
  OR SUM(p.p05) > 30
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;