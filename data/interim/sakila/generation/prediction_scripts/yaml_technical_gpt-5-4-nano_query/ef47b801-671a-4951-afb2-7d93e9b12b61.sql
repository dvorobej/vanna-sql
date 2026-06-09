SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  c.h02 AS store_id,
  COUNT(p.p01) AS payment_count,
  ROUND(AVG(p.p05), 2) AS avg_payment_amount,
  ROUND(MAX(p.p05), 2) AS max_payment_amount,
  CASE
    WHEN COUNT(p.p01) > 10 THEN 1
    ELSE 0
  END AS additional_check_required
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  c.h02
HAVING SUM(p.p05) > 50
ORDER BY payment_count DESC, total_payment_amount DESC, c.h01;