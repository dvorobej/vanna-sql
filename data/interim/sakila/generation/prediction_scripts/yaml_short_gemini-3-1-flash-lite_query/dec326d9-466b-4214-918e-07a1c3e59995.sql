WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS daily_count,
        SUM(p.p05) AS daily_amount,
        COUNT(DISTINCT p.p03) AS daily_staff_count,
        COUNT(DISTINCT s.o07) AS daily_store_count,
        COUNT(DISTINCT r.q03) AS daily_film_count
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    LEFT JOIN ren r ON r.q01 = p.p04
    GROUP BY p.p02, DATE(p.p06)
),
window_stats AS (
    SELECT
        customer_id,
        payment_date,
        SUM(daily_amount) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_amount,
        SUM(daily_count) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_count,
        SUM(daily_film_count) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_film_count,
        AVG(daily_amount) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 36 PRECEDING AND 7 PRECEDING) AS hist_avg_amount,
        AVG(daily_count) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 36 PRECEDING AND 7 PRECEDING) AS hist_avg_count
    FROM daily_customer_stats
),
suspicious_events AS (
    SELECT
        ws.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM window_stats ws
    JOIN cus c ON c.h01 = ws.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE ws.window_amount >= 3 * ws.hist_avg_amount
      AND ws.window_count >= 5
      AND ws.hist_avg_amount IS NOT NULL
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (ORDER BY window_amount DESC) AS global_suspicious_rank
    FROM suspicious_events
)
SELECT
    customer_name,
    country,
    city,
    payment_date AS window_end_date,
    window_amount,
    window_count,
    window_film_count,
    global_suspicious_rank
FROM ranked_suspicious
ORDER BY global_suspicious_rank;