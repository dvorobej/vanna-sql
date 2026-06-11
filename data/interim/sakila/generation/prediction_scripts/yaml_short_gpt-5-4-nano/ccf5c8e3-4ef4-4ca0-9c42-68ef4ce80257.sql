SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  MAX(p.p05) AS max_payment,
  CASE
    WHEN MAX(p.p05) > 9.99 THEN 'высокий'
    ELSE 'обычный'
  END AS payment_level
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;