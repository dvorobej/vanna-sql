SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  SUM(p.p05) AS total_payment_amount,
  AVG(p.p05) AS average_payment_amount,
  CASE
    WHEN MAX(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) = 1 THEN 1
    ELSE 0
  END AS suspicious_activity
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
ORDER BY
  total_payment_amount DESC;