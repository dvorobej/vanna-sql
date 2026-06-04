SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    c.c04 AS client_state,
    a.a02 AS account_number,
    COUNT(t.t01) AS transaction_count,
    COALESCE(SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END), 0) AS total_debits,
    COALESCE(SUM(CASE WHEN t.t02 > 0 THEN  t.t02 ELSE 0 END), 0) AS total_credits,
    COALESCE(
        SUM(CASE WHEN t.t01 IS NOT NULL AND t.t04 <> c.c04 THEN 1 ELSE 0 END) * 1.0
        / NULLIF(COUNT(t.t01), 0),
        0
    ) AS out_of_state_transaction_share
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
LEFT JOIN btm_trn AS t
    ON t.t01 = a.a02
   AND t.t05 >= '2020-01-01'
   AND t.t05 < '2021-01-01'
WHERE c.c04 = 'CA'
  AND a.a03 = 'SAVINGS'
  AND a.a05 = 'ACTIVE'
GROUP BY
    c.c01,
    c.c02,
    c.c04,
    a.a02
ORDER BY
    c.c01,
    a.a02;