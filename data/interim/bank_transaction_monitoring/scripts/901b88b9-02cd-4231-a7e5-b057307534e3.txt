SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    a.a03 AS account_type,
    COUNT(t.t01) AS transaction_count,
    SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END) AS total_debits,
    SUM(CASE WHEN t.t02 > 0 THEN  t.t02 ELSE 0 END) AS total_credits,
    AVG(CASE WHEN t.t04 <> c.c04 THEN 1.0 ELSE 0.0 END) AS out_of_state_transaction_share
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE a.a05 = 'ACTIVE'
  AND t.t05 >= '2020-01-01'
  AND t.t05 <  '2020-04-01'
GROUP BY
    c.c01,
    c.c02,
    a.a03
HAVING SUM(ABS(t.t02)) > 10000;