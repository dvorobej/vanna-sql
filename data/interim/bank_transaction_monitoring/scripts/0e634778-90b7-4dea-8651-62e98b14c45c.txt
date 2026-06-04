SELECT
    c.c01 AS customer_id,
    c.c02 AS customer_name,
    a.s03 AS account_type,
    COUNT(t.t01) AS transaction_count,
    SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END) AS total_debits,
    SUM(CASE WHEN t.t02 > 0 THEN t.t02 ELSE 0 END) AS total_credits,
    CASE
        WHEN a.s05 = 'ACTIVE'
             AND SUM(CASE WHEN t.t02 < 0 THEN -t.t02 ELSE 0 END) > 10000
        THEN 1
        ELSE 0
    END AS risk_flag
FROM btm_cst AS c
JOIN btm_accs AS a
    ON a.s01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.s02
WHERE t.t05 >= '2020-01-01'
  AND t.t05 < '2020-04-01'
GROUP BY
    c.c01,
    c.c02,
    a.s03,
    a.s05
ORDER BY
    c.c01,
    a.s03;