SELECT
  c.h01 AS customer_id,
  c.h02 AS store_id,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS avg_payment,
  MAX(p.p05) AS max_payment,
  SUM(CASE WHEN p.p05 > 8.00 THEN p.p05 ELSE 0 END) / SUM(p.p05) AS share_of_large_payments_in_total
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h02
HAVING SUM(p.p05) > 50
ORDER BY SUM(p.p05) DESC;