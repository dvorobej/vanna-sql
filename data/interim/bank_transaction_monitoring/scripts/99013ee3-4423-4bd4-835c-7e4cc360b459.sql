SELECT
    c.c04 AS client_state,
    a.a03 AS account_type,
    COUNT(DISTINCT c.c01) AS unique_clients,
    COUNT(*) AS transaction_count,
    SUM(CASE WHEN t.t02 < 0 THEN ABS(t.t02) ELSE 0 END) AS total_debits,
    SUM(CASE WHEN t.t02 > 0 THEN t.t02 ELSE 0 END) AS total_credits,
    AVG(CASE WHEN t.t04 <> c.c04 THEN 1.0 ELSE 0.0 END) AS out_of_state_transaction_share
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE t.t05 >= '2020-01-01'
  AND t.t05 < '2020-02-01'
GROUP BY
    c.c04,
    a.a03
ORDER BY
    c.c04,
    a.a03;