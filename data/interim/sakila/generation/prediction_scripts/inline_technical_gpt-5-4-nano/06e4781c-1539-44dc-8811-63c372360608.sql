SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS avg_payment_amount,
  CAST(SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) AS REAL) / COUNT(p.p01) AS share_payments_over_5
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) >= 5
ORDER BY
  payment_count DESC,
  total_amount DESC,
  customer_id;