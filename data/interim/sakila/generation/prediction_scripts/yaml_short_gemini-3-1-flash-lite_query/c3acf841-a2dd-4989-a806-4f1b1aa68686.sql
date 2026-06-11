SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.o01 AS staff_id,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 30 THEN 'Повышенное внимание'
    ELSE 'Обычный'
  END AS attention_flag
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
JOIN stf AS s
  ON p.p03 = s.o01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01
HAVING COUNT(p.p01) >= 5
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;