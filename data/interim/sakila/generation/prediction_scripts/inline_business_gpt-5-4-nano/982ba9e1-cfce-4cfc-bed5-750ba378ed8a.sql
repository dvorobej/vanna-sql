SELECT
  p01 AS payment_id,
  p02 AS customer_id,
  p03 AS staff_id,
  p05 AS amount,
  p06 AS payment_datetime
FROM pay
WHERE p05 > 9.00
ORDER BY p06 DESC
LIMIT 20;