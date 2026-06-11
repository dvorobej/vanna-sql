SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_payment_amount,
  AVG(p.p05) AS avg_payment_amount,
  ROUND(
    1.0 * SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) / COUNT(p.p01),
    4
  ) AS staff_from_other_store_share
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE
  p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  COUNT(p.p01) > 5
  AND SUM(p.p05) > 30
ORDER BY
  total_payment_amount DESC,
  payment_count DESC,
  customer_id;