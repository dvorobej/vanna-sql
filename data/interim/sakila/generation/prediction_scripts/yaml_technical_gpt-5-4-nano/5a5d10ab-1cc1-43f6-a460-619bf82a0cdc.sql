SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS payments_over_8
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE
  c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  SUM(p.p05) > 30.00
ORDER BY total_amount DESC, payment_count DESC, customer_id;