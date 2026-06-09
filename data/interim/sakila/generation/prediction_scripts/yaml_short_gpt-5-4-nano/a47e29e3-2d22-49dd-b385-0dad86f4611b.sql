SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  s.j01 AS store_id,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS avg_payment_amount,
  MAX(p.p05) AS max_payment_amount,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS share_payments_above_8
FROM cus AS c
JOIN sto AS s
  ON s.j01 = c.h02
JOIN pay AS p
  ON p.p02 = c.h01
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
  AND SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) > 0.0
ORDER BY
  share_payments_above_8 DESC,
  payment_count DESC,
  MAX(p.p05) DESC;