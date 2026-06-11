SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.j01 AS store_id,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS avg_check,
  ROUND(MAX(p.p05), 2) AS max_check,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01),
    4
  ) AS share_payments_over_8
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS sf
  ON sf.o01 = p.p03
JOIN sto AS s
  ON s.j01 = c.h02
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.j01
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC, payment_count DESC, customer_id, store_id;