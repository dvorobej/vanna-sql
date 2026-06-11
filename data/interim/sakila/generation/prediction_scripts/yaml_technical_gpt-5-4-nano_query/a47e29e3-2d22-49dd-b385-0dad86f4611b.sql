SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  c.h02 AS store_id,
  COUNT(p.p01) AS payment_count,
  ROUND(AVG(p.p05), 2) AS avg_payment_amount,
  MAX(p.p05) AS max_payment_amount,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN p.p05 ELSE 0 END) / NULLIF(SUM(p.p05), 0),
    4
  ) AS share_large_amount_over_8
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  c.h02
HAVING SUM(p.p05) > 50
ORDER BY
  SUM(p.p05) DESC,
  payment_count DESC;