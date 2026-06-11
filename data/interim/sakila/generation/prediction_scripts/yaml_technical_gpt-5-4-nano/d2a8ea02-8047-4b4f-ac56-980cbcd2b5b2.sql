SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(*) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN AVG(p.p05) > 7.00 THEN 1
    ELSE 0
  END AS high_risk
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(*) >= 5
   AND SUM(p.p05) > 30
ORDER BY total_amount DESC, c.h01;