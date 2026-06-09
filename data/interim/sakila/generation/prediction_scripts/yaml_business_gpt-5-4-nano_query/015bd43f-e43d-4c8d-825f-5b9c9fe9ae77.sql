SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_payment_amount,
  AVG(p.p05) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 50 THEN 1
    ELSE 0
  END AS high_attention_flag
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) >= 5
ORDER BY total_payment_amount DESC;