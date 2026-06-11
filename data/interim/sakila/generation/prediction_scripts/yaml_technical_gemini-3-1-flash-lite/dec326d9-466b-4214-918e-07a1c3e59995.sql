WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(p.p01) AS daily_count
    FROM pay AS p
    GROUP BY p.p02, DATE(p.p06)
),
window_metrics AS (
    SELECT
        dp.customer_id,
        dp.payment_date AS window_end,
        SUM(dp.daily_amount) OVER (
            PARTITION BY dp.customer_id
            ORDER BY JULIANDAY(dp.payment_date)
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS window_amount,
        SUM(dp.daily_count) OVER (
            PARTITION BY dp.customer_id
            ORDER BY JULIANDAY(dp.payment_date)
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS window_count,
        (
            SELECT AVG(sub.daily_amount)
            FROM daily_payments AS sub
            WHERE sub.customer_id = dp.customer_id
              AND sub.payment_date >= DATE(dp.payment_date, '-37 days')
              AND sub.payment_date < DATE(dp.payment_date, '-7 days')
        ) AS historical_avg_amount
    FROM daily_payments AS dp
),
suspicious_windows AS (
    SELECT *
    FROM window_metrics
    WHERE window_amount >= 3 * COALESCE(historical_avg_amount, 0)
      AND window_count >= 5
      AND historical_avg_amount > 0
),
enriched_data AS (
    SELECT
        sw.customer_id,
        sw.window_end,
        sw.window_amount,
        sw.window_count,
        COUNT(DISTINCT i.n02) AS unique_films_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count
    FROM suspicious_windows AS sw
    JOIN pay AS p ON p.p02 = sw.customer_id
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    WHERE DATE(p.p06) BETWEEN DATE(sw.window_end, '-6 days') AND sw.window_end
    GROUP BY sw.customer_id, sw.window_end
)
SELECT
    RANK() OVER (ORDER BY ed.window_amount DESC) AS suspicion_rank,
    ed.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    ed.window_end AS window_end_date,
    ed.window_amount,
    ed.window_count,
    ed.unique_films_count,
    ed.staff_count,
    ed.store_count
FROM enriched_data AS ed
JOIN cus AS c ON c.h01 = ed.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY suspicion_rank;