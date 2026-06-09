SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.o07 AS store_id,
  COUNT(p.p01) AS payment_count,
  ROUND(AVG(p.p05), 2) AS avg_payment_amount,
  MAX(p.p05) AS max_payment_amount,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN p.p05 ELSE 0 END) / SUM(p.p05),
    4
  ) AS share_large_payments_sum_over_8
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o07
HAVING SUM(p.p05) > 50
ORDER BY
  SUM(p.p05) DESC,
  payment_count DESC;