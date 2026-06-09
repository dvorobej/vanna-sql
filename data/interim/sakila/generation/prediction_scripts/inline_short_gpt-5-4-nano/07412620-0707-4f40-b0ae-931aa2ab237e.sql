WITH juli AS (
  SELECT
    c.h01,
    c.h03,
    c.h04,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS total_amount,
    AVG(p.p05) AS avg_payment_amount,
    SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS large_payments_count
  FROM cus AS c
  JOIN pay AS p
    ON p.p02 = c.h01
  WHERE c.h07 IN ('1', 'Y')
    AND p.p06 >= '2005-06-01'
    AND p.p06 < '2005-07-01'
  GROUP BY c.h01, c.h03, c.h04
)
SELECT
  h01 AS customer_id,
  h03 AS first_name,
  h04 AS last_name,
  payment_count,
  total_amount,
  avg_payment_amount,
  large_payments_count
FROM juli
WHERE payment_count >= 5
  AND (1.0 * large_payments_count / payment_count) > 0.30
ORDER BY total_amount DESC, payment_count DESC;