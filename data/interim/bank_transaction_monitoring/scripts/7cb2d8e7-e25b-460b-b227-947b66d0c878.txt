SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    a.a03 AS account_type,
    COUNT(t.t01) AS transaction_count,
    SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END) AS total_debits,
    SUM(CASE WHEN t.t02 > 0 THEN t.t02 ELSE 0 END) AS total_credits,
    ROUND(
        1.0 * SUM(CASE WHEN t.t01 IS NOT NULL AND t.t04 <> c.c04 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(t.t01), 0),
        4
    ) AS out_of_state_transaction_share
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
LEFT JOIN btm_trn AS t
    ON t.t01 = a.a02
   AND t.t05 >= '2020-01-01'
   AND t.t05 < '2021-01-01'
WHERE a.a05 = 'ACTIVE'
GROUP BY
    c.c01,
    c.c02,
    a.a03
ORDER BY
    c.c01,
    a.a03;