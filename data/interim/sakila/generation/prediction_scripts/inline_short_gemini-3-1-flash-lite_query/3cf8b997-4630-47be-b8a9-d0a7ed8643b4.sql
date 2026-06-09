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
        ) AS prev_avg_sum
    FROM monthly_stats
),
suspicious_months AS (
    SELECT
        rs.*,
        c.h02 AS store_id,
        ct.d02 AS city,
        cn.c02 AS country
    FROM rolling_stats rs
    JOIN cus c ON c.h01 = rs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    WHERE rs.prev_avg_sum IS NOT NULL
      AND rs.monthly_sum >= 2 * rs.prev_avg_sum
      AND rs.payment_count >= 3
),
store_ranks AS (
    SELECT
        *,
        PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY monthly_sum DESC) as store_percentile
    FROM suspicious_months
),
top_clients AS (
    SELECT customer_id
    FROM store_ranks
    WHERE store_percentile <= 0.1
    GROUP BY customer_id
    HAVING COUNT(payment_month) = 12
),
staff_agg AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_sum
    FROM pay p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
),
top_staff AS (
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id, payment_month ORDER BY staff_sum DESC) as rn
        FROM staff_agg
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
    RANK() OVER (PARTITION BY sr.store_id, sr.payment_month ORDER BY sr.monthly_sum DESC) as store_rank,
    st.o02 || ' ' || st.o03 AS top_staff_name
FROM store_ranks sr
JOIN top_clients tc ON sr.customer_id = tc.customer_id
JOIN top_staff ts ON ts.customer_id = sr.customer_id AND ts.payment_month = sr.payment_month
JOIN stf st ON st.o01 = ts.staff_id
ORDER BY sr.payment_month, sr.store_id, store_rank;