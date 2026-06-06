SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    c.c04 AS client_state,
    a.s03 AS account_type,
    SUM(CASE WHEN t.t02 < 0 THEN ABS(t.t02) ELSE 0 END) AS total_debits,
    SUM(CASE WHEN t.t02 > 0 THEN t.t02 ELSE 0 END) AS total_credits,
    COUNT(*) AS transaction_count,
    1.0 * SUM(CASE WHEN t.t04 IS NOT NULL AND t.t04 <> c.c04 THEN 1 ELSE 0 END) / COUNT(*) AS out_of_state_transaction_share
FROM btm_cst AS c
JOIN btm_accs AS a
    ON a.s01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.s02
WHERE c.c04 = 'CA'
  AND a.s05 = 'ACTIVE'
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2020-04-01'
GROUP BY
    c.c01,
    c.c02,
    c.c04,
    a.s03
ORDER BY
    c.c01,
    a.s03;