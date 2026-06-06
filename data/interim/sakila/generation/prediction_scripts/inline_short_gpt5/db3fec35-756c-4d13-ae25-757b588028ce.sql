WITH june_customers AS (
  SELECT
    p02 AS customer_id
  FROM pay
  WHERE p06 >= '2005-06-01'
    AND p06 < '2005-07-01'
  GROUP BY p02
  HAVING COUNT(p01) > 10
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS transaction_count,
  ROUND(SUM(p.p05), 2) AS total_payment_amount,
  ROUND(AVG(p.p05), 2) AS average_check,
  SUM(CASE WHEN p.p05 >= 5.00 THEN 1 ELSE 0 END) AS payments_amount_ge_5
FROM pay AS p
JOIN june_customers AS jc
  ON jc.customer_id = p.p02
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
  s.o01,
  s.o02,
  s.o03
ORDER BY
  c.h01,
  s.o01;