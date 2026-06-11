SELECT
  c.c02 AS first_name,
  c.c03 AS last_name,
  COUNT(t.t01) AS transaction_count,
  SUM(t.t02) AS total_amount,
  AVG(t.t02) AS average_amount,
  CASE
    WHEN SUM(t.t02) > 100 THEN 'высокий'
    ELSE 'средний'
  END AS risk_level
FROM btm_cst AS c
JOIN btm_accd AS a
  ON c.c01 = a.a01
JOIN btm_trn AS t
  ON a.a02 = t.t01
WHERE t.t05 >= '2005-07-01'
  AND t.t05 < '2005-08-01'
GROUP BY
  c.c01,
  c.c02,
  c.c03
HAVING COUNT(t.t01) > 10
    OR SUM(t.t02) > 50;