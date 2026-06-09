SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  c.h02 AS store_id,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS average_payment,
  MAX(p.p05) AS max_payment,
  AVG(CASE WHEN p.p05 > 8.00 THEN 1.0 ELSE 0.0 END) AS share_payments_above_8
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  c.h02
HAVING SUM(p.p05) > 50
ORDER BY SUM(p.p05) DESC;