SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  DATE(p.p06) AS payment_date,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  MAX(p.p05) AS max_payment,
  CASE
    WHEN COUNT(p.p01) >= 3 OR SUM(p.p05) > 20 THEN 'подозрительная активность'
    ELSE 'норма'
  END AS suspicious_flag
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  DATE(p.p06)
HAVING COUNT(p.p01) >= 3
    OR SUM(p.p05) > 20
ORDER BY total_amount DESC, payment_count DESC;