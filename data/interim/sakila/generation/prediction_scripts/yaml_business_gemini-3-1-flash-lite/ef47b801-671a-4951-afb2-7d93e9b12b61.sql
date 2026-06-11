SELECT
  c.h02 AS store_id,
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS average_payment,
  MAX(p.p05) AS max_payment,
  CASE
    WHEN COUNT(p.p01) > 10 THEN 'требует проверки'
    ELSE 'норма'
  END AS check_status
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h02,
  c.h01,
  c.h03,
  c.h04
HAVING SUM(p.p05) > 50
ORDER BY
  c.h02,
  SUM(p.p05) DESC;