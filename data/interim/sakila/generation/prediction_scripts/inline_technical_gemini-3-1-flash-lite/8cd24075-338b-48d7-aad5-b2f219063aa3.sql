SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  c.h05 AS email,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_amount,
  CASE
    WHEN SUM(p.p05) > 100 OR AVG(p.p05) > 8.00 THEN 'высокий'
    ELSE 'обычный'
  END AS risk_flag
FROM cus AS c
JOIN pay AS p
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 <= '2005-07-31 23:59:59'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  c.h05
HAVING COUNT(p.p01) >= 5
ORDER BY
  total_amount DESC,
  payment_count DESC;