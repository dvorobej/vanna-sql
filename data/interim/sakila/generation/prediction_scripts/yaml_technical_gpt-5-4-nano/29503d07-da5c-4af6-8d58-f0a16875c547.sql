SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS avg_payment,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS large_payment_count
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
  AND p.p04 IS NOT NULL
  AND c.h07 = '1'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  SUM(p.p05) > 50.00
  OR SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) >= 3
ORDER BY total_amount DESC, payment_count DESC, customer_id;