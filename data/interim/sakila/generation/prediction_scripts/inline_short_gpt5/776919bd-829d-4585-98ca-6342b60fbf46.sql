SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(COALESCE(SUM(p.p05), 0), 2) AS total_amount,
  ROUND(COALESCE(AVG(p.p05), 0), 2) AS avg_payment,
  CASE
    WHEN COUNT(p.p01) > 10 OR COALESCE(SUM(p.p05), 0) > 50.00 THEN 1
    ELSE 0
  END AS suspicious_activity
FROM cus AS c
LEFT JOIN pay AS p
  ON p.p02 = c.h01
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
WHERE c.h07 IN ('1', 'Y')
GROUP BY
  c.h01,
  c.h03,
  c.h04
ORDER BY
  suspicious_activity DESC,
  total_amount DESC,
  payment_count DESC;