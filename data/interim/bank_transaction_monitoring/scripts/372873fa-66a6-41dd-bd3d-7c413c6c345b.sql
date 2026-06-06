SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    t.t04 AS transaction_state,
    COUNT(*) AS total_transactions,
    SUM(t.t02) AS total_transaction_amount,
    SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END) AS outgoing_transaction_amount
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE a.a03 = 'SAVINGS'
  AND a.a05 = 'ACTIVE'
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2020-04-01'
GROUP BY
    c.c01,
    c.c02,
    t.t04
HAVING SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END) > 10000
ORDER BY
    c.c01,
    t.t04;