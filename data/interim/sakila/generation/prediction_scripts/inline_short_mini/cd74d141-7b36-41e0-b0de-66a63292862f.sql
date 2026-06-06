SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  ROUND(MAX(p.p05), 2) AS max_payment,
  CASE
    WHEN MAX(p.p05) > 3 * AVG(p.p05) THEN 1
    ELSE 0
  END AS risk_flag
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) >= 10
ORDER BY
  risk_flag DESC,
  total_amount DESC,
  payment_count DESC;