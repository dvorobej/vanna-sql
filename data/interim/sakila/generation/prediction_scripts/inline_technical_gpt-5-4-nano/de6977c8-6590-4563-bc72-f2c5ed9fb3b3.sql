SELECT
  c.h01 AS customer_id,
  p.p03 AS staff_id,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) / COUNT(p.p01),
    4
  ) AS share_payments_above_5
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  p.p03
HAVING COUNT(p.p01) >= 5
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id,
  staff_id;