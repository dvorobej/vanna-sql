SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  COALESCE(SUM(p.p05), 0) AS total_amount,
  AVG(p.p05) AS avg_amount,
  CASE
    WHEN COUNT(p.p01) > 10 OR COALESCE(SUM(p.p05), 0) > 50 THEN 'подозрительно'
    ELSE 'норма'
  END AS risk_mark
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  COUNT(p.p01) > 10
  OR COALESCE(SUM(p.p05), 0) > 50
ORDER BY
  total_amount DESC,
  payment_count DESC;