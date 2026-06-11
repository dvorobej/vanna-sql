WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS activity_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count,
        COUNT(DISTINCT r.q03) AS inventory_count
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    JOIN ren r ON r.q01 = p.p04
    GROUP BY p.p02, DATE(p.p06)
),
window_activity AS (
    SELECT
        d1.customer_id,
        d1.activity_date AS window_end_date,
        SUM(d2.daily_amount) AS window_amount,
        SUM(d2.daily_count) AS window_count,
        MAX(d2.staff_count) AS max_staff_in_window,
        MAX(d2.store_count) AS max_store_in_window,
        SUM(d2.inventory_count) AS total_inventory_in_window,
        (SELECT AVG(d3.daily_amount) 
         FROM daily_activity d3 
         WHERE d3.customer_id = d1.customer_id 
           AND d3.activity_date >= DATE(d1.activity_date, '-30 days') 
           AND d3.activity_date < d1.activity_date) AS hist_avg_daily_amount
    FROM daily_activity d1
    JOIN daily_activity d2 ON d2.customer_id = d1.customer_id
      AND d2.activity_date BETWEEN DATE(d1.activity_date, '-6 days') AND d1.activity_date
    GROUP BY d1.customer_id, d1.activity_date
),
suspicious_windows AS (
    SELECT
        wa.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country
    FROM window_activity wa
    JOIN cus c ON c.h01 = wa.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    WHERE wa.window_amount >= 3 * COALESCE(wa.hist_avg_daily_amount * 7, 0)
      AND wa.window_count >= 5
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (ORDER BY window_amount DESC) AS global_suspicious_rank
    FROM suspicious_windows
)
SELECT
    customer_name,
    country,
    city,
    window_end_date,
    window_amount,
    window_count,
    max_staff_in_window,
    max_store_in_window,
    total_inventory_in_window,
    global_suspicious_rank
FROM ranked_suspicious
ORDER BY global_suspicious_rank;