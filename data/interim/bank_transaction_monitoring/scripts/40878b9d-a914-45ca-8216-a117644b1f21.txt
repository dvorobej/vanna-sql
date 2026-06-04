SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    COUNT(t.t01) AS operation_count,
    COALESCE(SUM(-t.t02), 0) AS total_debit_amount,
    AVG(-t.t02) AS avg_debit_operation_amount
FROM btm_cst AS c
JOIN btm_accs AS s
    ON s.s01 = c.c01
   AND s.s03 = 'SAVINGS'
   AND s.s05 = 'ACTIVE'
LEFT JOIN btm_trn AS t
    ON t.t01 = s.s02
   AND t.t02 < 0
   AND t.t05 >= '2020-01-01'
   AND t.t05 < '2021-01-01'
WHERE c.c04 = 'CA'
GROUP BY
    c.c01,
    c.c02
ORDER BY
    c.c01;