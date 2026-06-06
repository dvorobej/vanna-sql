SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  c.h05 AS customer_email,
  COUNT(p.p01) AS total_transactions,
  ROUND(SUM(p.p05), 2) AS total_payments,
  ROUND(AVG(p.p05), 2) AS average_check,
  SUM(CASE WHEN p.p05 >= 5.00 THEN 1 ELSE 0 END) AS operations_at_least_5,
  GROUP_CONCAT(DISTINCT s.o02 || ' ' || s.o03) AS staff_members
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
  c.h05
HAVING COUNT(p.p01) > 10
ORDER BY
  total_transactions DESC,
  total_payments DESC;