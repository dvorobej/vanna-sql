SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.j01 AS store_id,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS avg_payment_amount,
  MAX(p.p05) AS max_payment_amount,
  AVG(CASE WHEN p.p05 > 8.00 THEN 1.0 ELSE 0.0 END) AS share_payments_above_8
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS f
  ON f.o01 = p.p03
JOIN sto AS s
  ON s.j01 = f.o07
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
ORDER BY
  payment_count DESC,
  avg_payment_amount DESC,
  customer_id,
  store_id;