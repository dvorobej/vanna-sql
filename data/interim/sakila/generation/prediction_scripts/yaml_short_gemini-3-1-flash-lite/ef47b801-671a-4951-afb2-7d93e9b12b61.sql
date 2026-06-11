SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  c.h02 AS store_id,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS avg_payment,
  MAX(p.p05) AS max_payment,
  CASE
    WHEN COUNT(p.p01) > 10 THEN 'High Frequency'
    ELSE 'Standard'
  END AS frequency_label
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  c.h02
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC, payment_count DESC;