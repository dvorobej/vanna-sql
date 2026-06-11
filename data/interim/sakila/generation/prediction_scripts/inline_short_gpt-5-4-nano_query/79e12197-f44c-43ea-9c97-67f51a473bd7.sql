SELECT
  p01 AS payment_id,
  p02 AS customer_id,
  p05 AS amount,
  p06 AS payment_date
FROM pay
ORDER BY p05 DESC
LIMIT 10;