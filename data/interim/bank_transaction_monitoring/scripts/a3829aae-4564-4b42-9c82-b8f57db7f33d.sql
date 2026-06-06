WITH active_savings AS (
    SELECT
        c.c01 AS client_id,
        c.c02 AS client_name,
        c.c04 AS client_state,
        s.s02 AS account_no,
        s.s04 AS current_balance
    FROM btm_cst AS c
    JOIN btm_accs AS s
        ON s.s01 = c.c01
    WHERE s.s03 = 'SAVINGS'
      AND s.s05 = 'ACTIVE'
),
suspicious_tx AS (
    SELECT
        a.client_id,
        a.account_no,
        t.t04 AS operation_state,
        t.t05 AS transaction_date,
        -t.t02 AS debit_amount
    FROM active_savings AS a
    JOIN btm_trn AS t
        ON t.t01 = a.account_no
    WHERE t.t02 < 0
      AND t.t05 >= '2020-01-01'
      AND t.t05 < '2021-01-01'
      AND t.t04 <> a.client_state
),
account_totals AS (
    SELECT
        a.client_id,
        a.client_name,
        a.client_state,
        a.account_no,
        a.current_balance,
        COALESCE(SUM(st.debit_amount), 0) AS total_suspicious_debits,
        COUNT(DISTINCT st.operation_state) AS distinct_operation_states
    FROM active_savings AS a
    LEFT JOIN suspicious_tx AS st
        ON st.client_id = a.client_id
       AND st.account_no = a.account_no
    GROUP BY
        a.client_id,
        a.client_name,
        a.client_state,
        a.account_no,
        a.current_balance
),
average_totals AS (
    SELECT
        AVG(total_suspicious_debits) AS avg_suspicious_debits
    FROM account_totals
),
largest_debit AS (
    SELECT
        client_id,
        account_no,
        transaction_date,
        ROW_NUMBER() OVER (
            PARTITION BY client_id, account_no
            ORDER BY debit_amount DESC, transaction_date ASC
        ) AS rn
    FROM suspicious_tx
),
qualified_clients AS (
    SELECT
        at.client_id,
        at.client_name,
        at.client_state,
        at.account_no,
        at.current_balance,
        at.total_suspicious_debits,
        at.distinct_operation_states
    FROM account_totals AS at
    CROSS JOIN average_totals AS av
    WHERE at.total_suspicious_debits > av.avg_suspicious_debits
)
SELECT
    q.client_name,
    q.client_state,
    q.account_no,
    q.current_balance,
    q.total_suspicious_debits,
    q.distinct_operation_states,
    ld.transaction_date AS largest_debit_date,
    RANK() OVER (
        ORDER BY q.total_suspicious_debits DESC
    ) AS suspicious_debit_rank
FROM qualified_clients AS q
LEFT JOIN largest_debit AS ld
    ON ld.client_id = q.client_id
   AND ld.account_no = q.account_no
   AND ld.rn = 1
ORDER BY
    suspicious_debit_rank,
    q.client_id,
    q.account_no;