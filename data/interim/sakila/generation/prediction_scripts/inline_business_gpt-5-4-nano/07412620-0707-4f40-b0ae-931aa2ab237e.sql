SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_check,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS large_payments_count,
  1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01) AS large_payments_ratio
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN sto AS s
  ON s.j01 = c.h02
JOIN adr AS a
  ON a.e01 = c.h06
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
  AND c.h07 = 'Y'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  COUNT(p.p01) >= 5
  AND (1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) / COUNT(p.p01)) > 0.30
ORDER BY total_amount DESC, payment_count DESC, c.h04, c.h03;