SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.j01 AS store_id,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS avg_payment_amount,
  MAX(p.p05) AS max_payment_amount,
  1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01) AS share_payments_above_8
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE
  p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.j01
HAVING
  SUM(p.p05) > 50
  AND 1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01) > 0;