SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  p.p03 AS staff_id,
  s.o02 || ' ' || s.o03 AS staff_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_check,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) / COUNT(p.p01),
    4
  ) AS share_payments_above_5
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  customer_name,
  p.p03,
  staff_id,
  staff_name
HAVING SUM(p.p05) > 50.00
ORDER BY total_amount DESC,
         payment_count DESC;