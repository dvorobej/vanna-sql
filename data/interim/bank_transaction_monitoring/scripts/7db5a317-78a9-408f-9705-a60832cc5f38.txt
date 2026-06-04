WITH active_savings_accounts AS (
    SELECT
        c.c01 AS customer_id,
        c.c02 AS customer_name,
        c.c04 AS customer_state,
        s.s02 AS account_number,
        UPPER(s.s03) AS account_type,
        s.s04 AS current_balance
    FROM btm_accs AS s
    JOIN btm_cst AS c
        ON c.c01 = s.s01
    WHERE UPPER(s.s03) = 'SAVINGS'
      AND UPPER(s.s05) = 'ACTIVE'
),
account_turnover AS (
    SELECT
        a.customer_id,
        a.customer_name,
        a.customer_state,
        a.account_number,
        a.account_type,
        a.current_balance,
        COALESCE(SUM(-t.t02), 0) AS total_outgoing_turnover,
        COUNT(t.t01) AS operation_count,
        CASE
            WHEN COUNT(t.t01) = 0 THEN NULL
            ELSE 1.0 * SUM(CASE WHEN t.t04 <> a.customer_state THEN 1 ELSE 0 END) / COUNT(t.t01)
        END AS out_of_home_state_share
    FROM active_savings_accounts AS a
    LEFT JOIN btm_trn AS t
        ON t.t01 = a.account_number
       AND t.t02 < 0
       AND t.t05 >= '2020-01-01'
       AND t.t05 < '2021-01-01'
    GROUP BY
        a.customer_id,
        a.customer_name,
        a.customer_state,
        a.account_number,
        a.account_type,
        a.current_balance
),
state_avg_turnover AS (
    SELECT
        customer_state,
        AVG(total_outgoing_turnover) AS avg_state_outgoing_turnover
    FROM account_turnover
    GROUP BY customer_state
),
active_balance_ordered AS (
    SELECT
        UPPER(s03) AS account_type,
        s04 AS current_balance,
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(s03)
            ORDER BY s04
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY UPPER(s03)
        ) AS cnt
    FROM btm_accs
    WHERE UPPER(s05) = 'ACTIVE'
),
median_balance_by_type AS (
    SELECT
        account_type,
        AVG(current_balance) AS median_active_balance
    FROM active_balance_ordered
    WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY account_type
),
ranked_accounts AS (
    SELECT
        at.*,
        DENSE_RANK() OVER (
            PARTITION BY at.customer_state
            ORDER BY at.total_outgoing_turnover DESC
        ) AS state_turnover_rank
    FROM account_turnover AS at
)
SELECT
    r.customer_id,
    r.customer_name,
    r.customer_state,
    r.account_number,
    r.current_balance,
    r.total_outgoing_turnover,
    r.operation_count,
    r.out_of_home_state_share,
    r.state_turnover_rank
FROM ranked_accounts AS r
JOIN state_avg_turnover AS sa
    ON sa.customer_state = r.customer_state
JOIN median_balance_by_type AS mb
    ON mb.account_type = r.account_type
WHERE r.total_outgoing_turnover > 2 * sa.avg_state_outgoing_turnover
  AND r.current_balance > mb.median_active_balance
ORDER BY
    r.customer_state,
    r.state_turnover_rank,
    r.customer_id,
    r.account_number;