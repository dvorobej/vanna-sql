SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    c.c04 AS home_state,
    SUM(-t.t02) AS total_debit_amount,
    COUNT(*) AS debit_operation_count,
    SUM(CASE WHEN t.t04 <> c.c04 THEN -t.t02 ELSE 0 END) AS out_of_state_debit_amount,
    SUM(CASE WHEN t.t04 <> c.c04 THEN 1 ELSE 0 END) AS out_of_state_debit_count
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE a.a03 = 'SAVINGS'
  AND a.a05 = 'ACTIVE'
  AND t.t02 < 0
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2020-02-01'
GROUP BY
    c.c01,
    c.c02,
    c.c04
HAVING SUM(CASE WHEN t.t04 <> c.c04 THEN -t.t02 ELSE 0 END) > 10000;