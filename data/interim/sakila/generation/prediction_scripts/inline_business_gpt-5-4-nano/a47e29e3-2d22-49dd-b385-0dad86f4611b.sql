SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  s.j01 AS store_id,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS avg_check,
  ROUND(MAX(p.p05), 2) AS max_check,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN p.p05 ELSE 0 END) / SUM(p.p05),
    4
  ) AS share_large_amount_over_8
FROM cus AS c
JOIN sto AS s
  ON s.j01 = c.h02
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.j01
HAVING SUM(p.p05) > 50
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;