SELECT
  c.h01 AS customer_id,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS payments_over_8,
  AVG(CASE WHEN p.p05 > 8.00 THEN 1.0 ELSE 0.0 END) AS share_payments_over_8
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE c.h07 = 'Y'
  AND p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01
HAVING COUNT(p.p01) >= 5
   AND (1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01)) > 0.30
ORDER BY
  c.h01;