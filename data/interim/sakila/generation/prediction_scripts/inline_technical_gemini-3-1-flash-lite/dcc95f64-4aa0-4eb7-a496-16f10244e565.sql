SELECT
  p.p02 AS customer_id,
  p.p03 AS staff_id,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
WHERE p.p05 > 5.00
  AND p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  p.p02,
  p.p03;