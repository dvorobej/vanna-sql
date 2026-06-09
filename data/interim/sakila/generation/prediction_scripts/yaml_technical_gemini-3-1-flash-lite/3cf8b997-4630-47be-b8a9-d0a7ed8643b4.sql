WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS top_staff_id -- Placeholder for logic below
    FROM pay p
    JOIN ren r ON p.p04 = r.q01 AND p.p02 = r.q04
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_history AS (
    SELECT
        *,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY month_start 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum,
        COUNT(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY month_start 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_customer_stats
),
suspicious_months AS (
    SELECT *
    FROM customer_history
    WHERE prev_months_count = 2
      AND monthly_sum >= 2 * prev_avg_sum
      AND payment_count >= 3
),
staff_monthly_sums AS (
    SELECT p.p02, date(p.p06, 'start of month') AS m_start, p.p03, SUM(p.p05) AS s
    FROM pay p
    GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
),
top_staff AS (
    SELECT m_start, p02, p03
    FROM (
        SELECT *, ROW_NUMBER() OVER(PARTITION BY p02, m_start ORDER BY s DESC) as rn
        FROM staff_monthly_sums
    ) WHERE rn = 1
),
store_rankings AS (
    SELECT
        sm.customer_id,
        sm.month_start,
        sm.monthly_sum,
        sm.payment_count,
        (sm.monthly_sum - sm.prev_avg_sum) AS deviation,
        c.h02 AS store_id,
        RANK() OVER (PARTITION BY c.h02, sm.month_start ORDER BY sm.monthly_sum DESC) AS store_rank,
        SUM(sm.monthly_sum) OVER (PARTITION BY c.h02, sm.customer_id) AS total_suspicious_sum_per_store
    FROM suspicious_months sm
    JOIN cus c ON sm.customer_id = c.h01
),
store_top_10_percent AS (
    SELECT *,
           PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY total_suspicious_sum_per_store DESC) as pr
    FROM store_rankings
)
SELECT
    st.customer_id,
    st.month_start,
    st.monthly_sum,
    st.payment_count,
    st.deviation,
    st.store_rank,
    sto.j01, adr.e02, cty.d02, cnt.c02,
    stf.o02 || ' ' || stf.o03 AS top_staff_name
FROM store_top_10_percent st
JOIN cus c ON st.customer_id = c.h01
JOIN sto ON c.h02 = sto.j01
JOIN adr ON sto.j03 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
JOIN top_staff ts ON st.customer_id = ts.p02 AND st.month_start = ts.m_start
JOIN stf ON ts.p03 = stf.o01
WHERE st.pr <= 0.1
ORDER BY st.store_id, st.month_start, st.monthly_sum DESC;