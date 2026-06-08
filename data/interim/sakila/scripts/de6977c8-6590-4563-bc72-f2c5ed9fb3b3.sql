WITH eligible_customers AS (
  SELECT
    p02 AS customer_id
  FROM pay
  WHERE p06 >= '2005-06-01'
    AND p06 < '2005-07-01'
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
  COUNT(*) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_check,
  ROUND(AVG(CASE WHEN p.p05 > 5.00 THEN 1.0 ELSE 0.0 END), 4) AS share_payments_above_5
FROM pay p
JOIN eligible_customers ec ON ec.customer_id = p.p02
JOIN cus c ON c.h01 = p.p02
JOIN stf s ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
ORDER BY
  payment_count DESC,
  total_amount DESC,
  customer_id,
  staff_id;