SELECT
  p.p02 AS customer_id,
  p.p03 AS staff_id,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 50 OR AVG(p.p05) > 8 THEN 1
    ELSE 0
  END AS attention_flag
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  p.p02,
  p.p03
HAVING COUNT(p.p01) >= 5
ORDER BY
  total_amount DESC,
  payment_count DESC,
  p.p02,
  p.p03;