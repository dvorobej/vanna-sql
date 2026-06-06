SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  GROUP_CONCAT(DISTINCT s.o02 || ' ' || s.o03) AS staff_names,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  MAX(p.p05) AS max_payment,
  CASE
    WHEN COUNT(p.p01) > 10 OR SUM(p.p05) > 50.00 THEN 1
    ELSE 0
  END AS suspicious_activity
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE c.h07 = 'Y'
  AND p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) > 10
    OR SUM(p.p05) > 50.00
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;