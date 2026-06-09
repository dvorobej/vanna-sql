SELECT
  p01 AS payment_id,
  p02 AS customer_id,
  p03 AS staff_id,
  p05 AS amount,
  p06 AS payment_date
FROM pay
WHERE p06 >= '2005-06-01'
  AND p06 < '2005-07-01'
ORDER BY p05 DESC
LIMIT 20;