SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS avg_payment_amount,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS payments_over_8,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01),
    4
  ) AS share_payments_over_8
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE
  c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  COUNT(p.p01) >= 5
  AND (
    1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01)
  ) > 0.30
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;