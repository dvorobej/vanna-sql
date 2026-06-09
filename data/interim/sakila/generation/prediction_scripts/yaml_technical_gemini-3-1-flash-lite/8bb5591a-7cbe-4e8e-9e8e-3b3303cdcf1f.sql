SELECT
  c.h01,
  c.h03,
  c.h04,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 50 THEN 'высокий'
    ELSE 'обычный'
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
HAVING COUNT(p.p01) > 10
   OR SUM(p.p05) > 50
ORDER BY total_amount DESC;