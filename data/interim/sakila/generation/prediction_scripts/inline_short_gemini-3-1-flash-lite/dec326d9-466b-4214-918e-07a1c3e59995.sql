WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        COUNT(DISTINCT r.q03) AS film_copy_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    GROUP BY p.p02, DATE(p.p06)
),
rolling_stats AS (
    SELECT
        dp.*,
        (
            SELECT SUM(dp2.day_amount)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= DATE(dp.payment_date, '-7 days')
              AND dp2.payment_date <= dp.payment_date
        ) AS amount_7d,
        (
            SELECT AVG(dp2.day_amount)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= DATE(dp.payment_date, '-30 days')
              AND dp2.payment_date < dp.payment_date
        ) AS avg_daily_30d
    FROM daily_payments AS dp
),
suspicious_activity AS (
    SELECT
        rs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM rolling_stats AS rs
    JOIN cus AS c ON c.h01 = rs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE rs.avg_daily_30d > 0
      AND rs.amount_7d > (3 * rs.avg_daily_30d)
      AND (rs.staff_count > 1 OR rs.store_count > 1)
),
ranked_suspicious AS (
    SELECT
        *,
        DENSE_RANK() OVER (ORDER BY amount_7d DESC) AS global_suspicious_rank
    FROM suspicious_activity
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    ROUND(amount_7d, 2) AS amount_7d,
    ROUND(avg_daily_30d, 2) AS avg_daily_30d,
    payment_count,
    staff_count,
    store_count,
    film_copy_count,
    global_suspicious_rank
FROM ranked_suspicious
ORDER BY global_suspicious_rank ASC;