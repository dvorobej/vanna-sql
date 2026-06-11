WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS top_staff_id -- Placeholder for logic below
    FROM pay p
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
rolling_stats AS (
    SELECT
        *,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum,
        COUNT(*) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
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
store_ranks AS (
    SELECT
        sm.*,
        c.h02 AS store_id,
        ct.d02 AS city,
        cn.c02 AS country,
        PERCENT_RANK() OVER (PARTITION BY c.h02 ORDER BY sm.monthly_sum DESC) AS store_percentile,
        RANK() OVER (PARTITION BY c.h02, sm.payment_month ORDER BY sm.monthly_sum DESC) AS store_rank
    FROM suspicious_months sm
    JOIN cus c ON sm.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt cn ON ct.d03 = cn.c01
),
top_staff_per_month AS (
    SELECT customer_id, payment_month, staff_id
    FROM (
        SELECT p.p02 AS customer_id, strftime('%Y-%m', p.p06) AS payment_month, p.p03 AS staff_id,
               ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    sr.store_id,
    sr.city,
    sr.country,
    sr.payment_month,
    sr.monthly_sum,
    sr.payment_count,
    (sr.monthly_sum - sr.prev_avg_sum) AS deviation,
    sr.store_rank,
    st.o02 || ' ' || st.o03 AS top_staff_name
FROM store_ranks sr
JOIN top_staff_per_month ts ON sr.customer_id = ts.customer_id AND sr.payment_month = ts.payment_month
JOIN stf st ON ts.staff_id = st.o01
WHERE sr.store_percentile <= 0.1
ORDER BY sr.store_id, sr.payment_month, sr.store_rank;