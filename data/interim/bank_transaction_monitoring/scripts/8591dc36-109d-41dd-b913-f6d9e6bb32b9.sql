WITH RECURSIVE months(month_start) AS (
    SELECT '2020-01-01'
    UNION ALL
    SELECT date(month_start, '+1 month')
    FROM months
    WHERE month_start < '2020-12-01'
),
linked_active_accounts AS (
    SELECT DISTINCT
        s.s01 AS client_id,
        COALESCE(NULLIF(r.r04, ''), s.s02) AS main_account,
        s.s02 AS linked_account
    FROM btm_accs AS s
    LEFT JOIN btm_rel AS r
        ON r.r02 = s.s02
       AND (
            r.r01 = s.s01
            OR r.r01 IS NULL
            OR CAST(r.r01 AS TEXT) = ''
       )
    WHERE s.s05 = 'ACTIVE'
),
account_groups AS (
    SELECT DISTINCT
        client_id,
        main_account
    FROM linked_active_accounts
),
monthly_outgoing AS (
    SELECT
        ag.client_id,
        ag.main_account,
        m.month_start,
        SUM(CASE WHEN t.t01 IS NOT NULL THEN -t.t02 ELSE 0 END) AS outgoing_turnover,
        SUM(CASE WHEN t.t01 IS NOT NULL AND t.t04 <> c.c04 THEN 1 ELSE 0 END) AS out_of_state_operation_count
    FROM account_groups AS ag
    CROSS JOIN months AS m
    JOIN btm_cst AS c
        ON c.c01 = ag.client_id
    LEFT JOIN linked_active_accounts AS la
        ON la.client_id = ag.client_id
       AND la.main_account = ag.main_account
    LEFT JOIN btm_trn AS t
        ON t.t01 = la.linked_account
       AND t.t02 < 0
       AND t.t05 >= m.month_start
       AND t.t05 < date(m.month_start, '+1 month')
    GROUP BY
        ag.client_id,
        ag.main_account,
        m.month_start
),
with_previous AS (
    SELECT
        mo.*,
        AVG(mo.outgoing_turnover) OVER (
            PARTITION BY mo.client_id, mo.main_account
            ORDER BY mo.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS previous_3_month_avg_outgoing,
        COUNT(*) OVER (
            PARTITION BY mo.client_id, mo.main_account
            ORDER BY mo.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS previous_month_count
    FROM monthly_outgoing AS mo
),
main_balances AS (
    SELECT
        s01 AS client_id,
        s02 AS main_account,
        MAX(s04) AS main_account_current_balance
    FROM btm_accs
    GROUP BY
        s01,
        s02
)
SELECT
    wp.client_id,
    c.c02 AS client_name,
    wp.main_account,
    strftime('%Y-%m', wp.month_start) AS violation_month,
    wp.outgoing_turnover AS total_outgoing_turnover,
    ROUND(wp.previous_3_month_avg_outgoing, 2) AS previous_3_month_avg_outgoing,
    wp.out_of_state_operation_count,
    mb.main_account_current_balance
FROM with_previous AS wp
JOIN btm_cst AS c
    ON c.c01 = wp.client_id
LEFT JOIN main_balances AS mb
    ON mb.client_id = wp.client_id
   AND mb.main_account = wp.main_account
WHERE wp.previous_month_count = 3
  AND wp.outgoing_turnover > 2.0 * wp.previous_3_month_avg_outgoing
  AND wp.out_of_state_operation_count > 0
ORDER BY
    wp.client_id,
    wp.main_account,
    wp.month_start;