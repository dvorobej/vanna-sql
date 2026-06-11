SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_check,
  CASE
    WHEN COUNT(p.p01) > 10 OR SUM(p.p05) > 80 THEN 1
    ELSE 0
  END AS suspicious_flag
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) > 10
    OR SUM(p.p05) > 80
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;