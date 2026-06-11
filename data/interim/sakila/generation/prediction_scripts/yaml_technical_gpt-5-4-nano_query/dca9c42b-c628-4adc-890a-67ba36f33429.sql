SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS payments_above_8
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE
  c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  COUNT(p.p01) > 10
  OR SUM(p.p05) > 50.00
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;