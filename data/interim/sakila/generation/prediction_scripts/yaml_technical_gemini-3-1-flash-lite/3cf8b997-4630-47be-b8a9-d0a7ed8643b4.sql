WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count
    FROM pay p
    JOIN ren r ON p.p04 = r.q01 AND p.p02 = r.q04
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
rolling_avg AS (
    SELECT
        customer_id,
        month,
        monthly_sum,
        payment_count,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum,
        COUNT(*) OVER (
            PARTITION BY customer_id 
            ORDER BY month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_stats
),
suspicious_months AS (
    SELECT *
    FROM rolling_avg
    WHERE prev_months_count = 2
      AND monthly_sum >= 2 * prev_avg_sum
      AND payment_count >= 3
),
staff_monthly AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_sum
    FROM pay p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
),
top_staff AS (
    SELECT customer_id, month, staff_id
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id, month ORDER BY staff_sum DESC) as rn
        FROM staff_monthly
    ) WHERE rn = 1
),
customer_rankings AS (
    SELECT
        sm.*,
        c.h02 AS store_id,
        RANK() OVER (PARTITION BY c.h02, sm.month ORDER BY sm.monthly_sum DESC) as store_rank,
        SUM(sm.monthly_sum) OVER (PARTITION BY c.h02, sm.customer_id) as total_suspicious_sum
    FROM suspicious_months sm
    JOIN cus c ON sm.customer_id = c.h01
),
top_10_percent AS (
    SELECT store_id, customer_id,
           PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY total_suspicious_sum DESC) as p_rank
    FROM (SELECT DISTINCT store_id, customer_id, total_suspicious_sum FROM customer_rankings)
)
SELECT
    cr.customer_id, cr.month, cr.monthly_sum, cr.payment_count,
    (cr.monthly_sum - cr.prev_avg_sum) AS deviation,
    cr.store_rank,
    st.j01, a.e02, ct.d02, cn.c02,
    s.o02 || ' ' || s.o03 AS top_staff_name
FROM customer_rankings cr
JOIN top_10_percent t10 ON cr.customer_id = t10.customer_id AND cr.store_id = t10.store_id
JOIN top_staff ts ON cr.customer_id = ts.customer_id AND cr.month = ts.month
JOIN stf s ON ts.staff_id = s.o01
JOIN sto st ON cr.store_id = st.j01
JOIN adr a ON st.j03 = a.e01
JOIN cty ct ON a.e05 = ct.d01
JOIN cnt cn ON ct.d03 = cn.c01
WHERE t10.p_rank <= 0.1
ORDER BY cr.store_id, cr.month, cr.monthly_sum DESC;