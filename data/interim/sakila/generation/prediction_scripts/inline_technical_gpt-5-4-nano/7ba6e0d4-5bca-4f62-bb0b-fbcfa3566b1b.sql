SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_payment_amount,
  AVG(p.p05) AS avg_payment_amount,
  CASE
    WHEN AVG(p.p05) > 5 THEN 'высокий'
    ELSE 'средний'
  END AS risk_level
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) >= 10
   AND SUM(p.p05) > 50
ORDER BY total_payment_amount DESC;