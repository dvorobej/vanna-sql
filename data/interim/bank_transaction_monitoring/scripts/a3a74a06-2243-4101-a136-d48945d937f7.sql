SELECT
  c.c01 AS client_id,
  c.c02 AS client_name,
  SUM(-t.t02) AS total_outgoing_amount,
  COUNT(*) AS outgoing_transaction_count,
  1.0 * SUM(CASE WHEN t.t04 <> c.c04 THEN 1 ELSE 0 END) / COUNT(*) AS out_of_state_share
FROM btm_cst AS c
JOIN btm_accd AS a
  ON a.a01 = c.c01
JOIN btm_trn AS t
  ON t.t01 = a.a02
WHERE a.a03 = 'SAVINGS'
  AND a.a05 = 'ACTIVE'
  AND t.t02 < 0
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2020-04-01'
GROUP BY
  c.c01,
  c.c02
HAVING SUM(-t.t02) > 10000
ORDER BY total_outgoing_amount DESC;