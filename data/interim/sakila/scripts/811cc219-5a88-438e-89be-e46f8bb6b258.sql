WITH july_clients AS (
  SELECT
    p02 AS customer_id
  FROM pay
  WHERE p06 >= '2005-07-01'
    AND p06 < '2005-08-01'
  GROUP BY p02
  HAVING COUNT(*) >= 5
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  CASE
    WHEN SUM(p.p05) > 50 OR AVG(p.p05) > 8 THEN 1
    ELSE 0
  END AS high_attention_flag
FROM pay AS p
JOIN july_clients AS jc
  ON jc.customer_id = p.p02
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id,
  staff_id;