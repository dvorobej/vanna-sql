SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    a.s02 AS account_number,
    COUNT(t.t01) AS transaction_count,
    SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END) AS total_debits,
    SUM(CASE WHEN t.t02 > 0 THEN t.t02 ELSE 0 END) AS total_credits,
    AVG(CASE WHEN t.t04 <> c.c04 THEN 1.0 ELSE 0.0 END) AS out_of_state_transaction_share
FROM btm_cst AS c
JOIN btm_accs AS a
    ON a.s01 = c.c01
LEFT JOIN btm_trn AS t
    ON t.t01 = a.s02
   AND t.t05 >= '2020-01-01'
   AND t.t05 < '2020-04-01'
WHERE a.s03 = 'SAVINGS'
  AND a.s05 = 'ACTIVE'
GROUP BY
    c.c01,
    c.c02,
    a.s02;