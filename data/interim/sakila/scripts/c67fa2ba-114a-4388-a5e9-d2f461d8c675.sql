SELECT
  p02 AS customer_id,
  p05 AS payment_amount,
  p06 AS payment_date
FROM pay
WHERE p05 > 9.00
ORDER BY p06 DESC
LIMIT 20;