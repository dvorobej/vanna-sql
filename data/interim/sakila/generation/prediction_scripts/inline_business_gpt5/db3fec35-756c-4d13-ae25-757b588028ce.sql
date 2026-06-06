SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  GROUP_CONCAT(DISTINCT s.o02 || ' ' || s.o03) AS staff_names,
  COUNT(p.p01) AS transaction_count,
  ROUND(SUM(p.p05), 2) AS total_payment_amount,
  ROUND(AVG(p.p05), 2) AS average_check,
  SUM(CASE WHEN p.p05 >= 5.00 THEN 1 ELSE 0 END) AS payments_at_least_5
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
  c.h04
HAVING COUNT(p.p01) > 10
ORDER BY
  transaction_count DESC,
  total_payment_amount DESC;