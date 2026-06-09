SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 100 OR AVG(p.p05) > 7.00 THEN 'высокий'
    ELSE 'обычный'
  END AS risk_flag
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-09-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) >= 10
ORDER BY total_amount DESC, payment_count DESC, c.h04, c.h03;