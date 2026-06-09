WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, date(p.p06, 'start of month')
),
rolling_stats AS (
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
    FROM monthly_stats
),
suspicious_months AS (
    SELECT *
    FROM rolling_stats
    WHERE prev_months_count = 2
      AND monthly_sum >= 2 * prev_avg_sum
      AND payment_count >= 3
),
staff_monthly AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_sum
    FROM pay p
    GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
),
top_staff AS (
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id, month_start ORDER BY staff_sum DESC) as rn
        FROM staff_monthly
    ) WHERE rn = 1
),
customer_store_rank AS (
    SELECT
        sm.customer_id,
        sm.month_start,
        sm.monthly_sum,
        sm.payment_count,
        (sm.monthly_sum - sm.prev_avg_sum) AS deviation,
        c.h02 AS store_id,
        RANK() OVER (PARTITION BY c.h02, sm.month_start ORDER BY sm.monthly_sum DESC) AS store_rank,
        SUM(sm.monthly_sum) OVER (PARTITION BY c.h02, sm.customer_id) AS total_suspicious_sum
    FROM suspicious_months sm
    JOIN cus c ON sm.customer_id = c.h01
),
store_percentiles AS (
    SELECT
        store_id,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY total_suspicious_sum) AS threshold
    FROM (SELECT DISTINCT customer_id, store_id, total_suspicious_sum FROM customer_store_rank)
    GROUP BY store_id
)
SELECT
    csr.*,
    st.o02 || ' ' || st.o03 AS top_staff_name,
    sto.j01, adr.e01, cty.d02, cnt.c02
FROM customer_store_rank csr
JOIN store_percentiles sp ON csr.store_id = sp.store_id
JOIN top_staff ts ON csr.customer_id = ts.customer_id AND csr.month_start = ts.month_start
JOIN stf st ON ts.staff_id = st.o01
JOIN cus c ON csr.customer_id = c.h01
JOIN sto ON c.h02 = sto.j01
JOIN adr ON sto.j03 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
WHERE csr.total_suspicious_sum >= sp.threshold
ORDER BY csr.store_id, csr.month_start, csr.store_rank;