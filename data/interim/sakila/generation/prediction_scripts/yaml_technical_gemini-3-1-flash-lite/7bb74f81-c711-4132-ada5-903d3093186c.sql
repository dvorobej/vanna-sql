SELECT
  p.p02 AS customer_id,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) AS count_payments_above_5
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
WHERE c.h07 = 'Y'
  AND p.p06 >= '2005-06-01'
  AND p.p06 <= '2005-06-30 23:59:59'
GROUP BY
  p.p02
HAVING COUNT(p.p01) > 10
   OR SUM(p.p05) > 50.00
ORDER BY
  total_amount DESC,
  payment_count DESC;