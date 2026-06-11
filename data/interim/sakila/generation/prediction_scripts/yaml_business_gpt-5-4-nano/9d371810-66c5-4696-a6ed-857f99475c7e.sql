SELECT
  p.p01 AS payment_id,
  p.p02 AS customer_id,
  p.p03 AS staff_id,
  p.p04 AS rental_id,
  p.p05 AS amount,
  p.p06 AS payment_date
FROM pay p
WHERE p.p05 > 8.00
ORDER BY p.p06 DESC
LIMIT 20;