SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  c.h02 AS store_id,
  SUM(p.p05) AS total_amount,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS average_payment,
  MAX(p.p05) AS max_payment,
  CASE
    WHEN COUNT(p.p01) > 10 THEN 1
    ELSE 0
  END AS additional_check_signal
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  c.h02
HAVING SUM(p.p05) > 50
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;