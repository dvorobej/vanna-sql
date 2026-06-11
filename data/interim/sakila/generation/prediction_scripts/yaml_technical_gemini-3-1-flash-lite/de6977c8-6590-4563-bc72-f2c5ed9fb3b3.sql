SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  p.p03 AS staff_id,
  COUNT(p.p01) AS transaction_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) / COUNT(p.p01),
    4
  ) AS share_payments_above_5
FROM cus AS c
JOIN pay AS p
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  p.p03
HAVING COUNT(p.p01) >= 5
ORDER BY
  c.h01,
  p.p03;