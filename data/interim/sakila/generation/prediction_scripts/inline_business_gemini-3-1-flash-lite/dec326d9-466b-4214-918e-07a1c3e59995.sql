WITH payment_windows AS (
    SELECT
        p.p02 AS customer_id,
        p.p06 AS payment_date,
        p.p05 AS amount,
        p.p03 AS staff_id,
        st.o07 AS store_id,
        r.q03 AS inventory_id
    FROM pay p
    JOIN stf st ON p.p03 = st.o01
    JOIN ren r ON p.p04 = r.q01
),
daily_stats AS (
    SELECT
        customer_id,
        DATE(payment_date) AS p_date,
        SUM(amount) AS daily_amount,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT staff_id) AS daily_staff,
        COUNT(DISTINCT store_id) AS daily_store,
        COUNT(DISTINCT inventory_id) AS daily_films
    FROM payment_windows
    GROUP BY customer_id, DATE(payment_date)
),
window_stats AS (
    SELECT
        d1.customer_id,
        d1.p_date AS window_end,
        SUM(d2.daily_amount) AS window_amount,
        SUM(d2.daily_count) AS window_count,
        SUM(d2.daily_films) AS window_films,
        COUNT(DISTINCT d2.p_date) AS days_in_window
    FROM daily_stats d1
    JOIN daily_stats d2 ON d2.customer_id = d1.customer_id
        AND d2.p_date BETWEEN DATE(d1.p_date, '-6 days') AND d1.p_date
    GROUP BY d1.customer_id, d1.p_date
),
history_stats AS (
    SELECT
        d1.customer_id,
        d1.p_date AS window_end,
        AVG(d2.daily_amount) AS hist_avg_daily
    FROM daily_stats d1
    JOIN daily_stats d2 ON d2.customer_id = d1.customer_id
        AND d2.p_date BETWEEN DATE(d1.p_date, '-36 days') AND DATE(d1.p_date, '-7 days')
    GROUP BY d1.customer_id, d1.p_date
),
suspicious_cases AS (
    SELECT
        ws.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country,
        RANK() OVER (ORDER BY ws.window_amount DESC) AS global_rank
    FROM window_stats ws
    JOIN history_stats hs ON ws.customer_id = hs.customer_id AND ws.window_end = hs.window_end
    JOIN cus c ON ws.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt cn ON ct.d03 = cn.c01
    WHERE ws.window_amount >= 3 * (hs.hist_avg_daily * 7)
      AND ws.window_count >= 5
)
SELECT
    customer_name,
    country,
    city,
    window_end AS period_end,
    window_amount,
    window_count,
    window_films,
    global_rank
FROM suspicious_cases
ORDER BY global_rank;