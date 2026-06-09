SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  c.h01 AS customer_id,
  SUM(p.p05) AS total_amount,
  COUNT(p.p01) AS payment_count,
  AVG(p.p05) AS avg_payment,
  MAX(p.p05) AS max_payment,
  1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01) AS share_payments_gt_8
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING SUM(p.p05) > 100;