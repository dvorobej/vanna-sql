SELECT
  p.p01 AS payment_id,
  p.p02 AS customer_id,
  p.p03 AS staff_id,
  p.p05 AS amount,
  p.p06 AS payment_date
FROM pay AS p
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
ORDER BY p.p05 DESC
LIMIT 10;