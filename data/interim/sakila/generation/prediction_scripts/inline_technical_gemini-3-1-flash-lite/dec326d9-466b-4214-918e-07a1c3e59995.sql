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
        dp.payment_date AS window_end_date,
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
            SELECT SUM(dp2.daily_amount) / 30.0
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= DATE(dp.payment_date, '-30 days')
              AND dp2.payment_date < dp.payment_date
        ) AS avg_daily_amount_prev_30
    FROM daily_payments AS dp
),
suspicious_windows AS (
    SELECT *
    FROM window_metrics
    WHERE avg_daily_amount_prev_30 > 0
      AND window_amount >= 3 * avg_daily_amount_prev_30
      AND window_count >= 5
),
detailed_info AS (
    SELECT
        sw.customer_id,
        sw.window_end_date,
        sw.window_amount,
        sw.window_count,
        COUNT(DISTINCT i.n02) AS unique_films_count
    FROM suspicious_windows AS sw
    JOIN pay AS p ON p.p02 = sw.customer_id
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    WHERE DATE(p.p06) BETWEEN DATE(sw.window_end_date, '-6 days') AND sw.window_end_date
    GROUP BY sw.customer_id, sw.window_end_date, sw.window_amount, sw.window_count
)
SELECT
    di.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    di.window_end_date,
    di.window_amount,
    di.window_count,
    di.unique_films_count,
    RANK() OVER (ORDER BY di.window_amount DESC) AS global_suspicion_rank
FROM detailed_info AS di
JOIN cus AS c ON c.h01 = di.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY global_suspicion_rank;