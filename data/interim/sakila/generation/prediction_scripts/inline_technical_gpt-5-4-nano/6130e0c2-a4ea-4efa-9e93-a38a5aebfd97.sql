SELECT
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment_amount,
  SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) AS payments_above_5
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE
  p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  COUNT(p.p01) >= 5
  AND SUM(p.p05) > 30
ORDER BY
  payment_count DESC,
  total_amount DESC,
  c.h01;