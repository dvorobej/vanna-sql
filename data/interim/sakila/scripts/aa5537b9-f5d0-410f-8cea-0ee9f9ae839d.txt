WITH customer_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS total_amount,
    AVG(p.p05) AS average_check,
    SUM(CASE WHEN p.p05 > 5.00 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS large_payment_share
  FROM cus AS c
  JOIN pay AS p
    ON p.p02 = c.h01
  WHERE p.p06 >= '2005-07-01'
    AND p.p06 < '2005-08-01'
  GROUP BY c.h01, c.h03, c.h04
  HAVING COUNT(p.p01) >= 5
)
SELECT
  customer_id,
  first_name,
  last_name,
  payment_count,
  ROUND(total_amount, 2) AS total_amount,
  ROUND(average_check, 2) AS average_check,
  ROUND(large_payment_share, 4) AS large_payment_share,
  CASE
    WHEN total_amount > 50.00 OR large_payment_share > 0.40 THEN 'Y'
    ELSE 'N'
  END AS suspicious_customer
FROM customer_payments
ORDER BY total_amount DESC, payment_count DESC, customer_id;