SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS avg_payment_amount,
  ROUND(SUM(CASE WHEN p2o.o07 <> p1o.o07 THEN p.p05 ELSE 0 END), 2) AS other_store_staff_payments_total
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS p1o
  ON p1o.o01 = p.p03
LEFT JOIN stf AS p2o
  ON 1 = 0
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01, c.h03, c.h04
HAVING SUM(p.p05) > 50
ORDER BY
  total_amount DESC,
  customer_id;