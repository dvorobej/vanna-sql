WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_payment_time,
        MAX(p.p06) AS last_payment_time,
        MAX(p.p05) AS max_payment
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_stats AS (
    SELECT
        dp.*,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= DATE(dp.payment_date, '-30 day')
              AND prev.payment_date < dp.payment_date
        ) AS avg_30d_amount,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM daily_payments AS dp
    JOIN cus AS c ON c.h01 = dp.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    WHERE dp.payment_count >= 3 AND dp.staff_count >= 2
),
country_percentiles AS (
    SELECT
        country_id,
        MAX(day_amount) AS p95_threshold
    FROM (
        SELECT country_id, day_amount,
               PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) as pr
        FROM customer_stats
    )
    WHERE pr <= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        cs.*,
        (cs.day_amount - cs.avg_30d_amount) AS deviation
    FROM customer_stats AS cs
    JOIN country_percentiles AS cp ON cs.country_id = cp.country_id
    WHERE cs.day_amount > cs.avg_30d_amount * 2
      AND cs.day_amount > cp.p95_threshold
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS total_amount,
    staff_count,
    store_count,
    first_payment_time,
    last_payment_time,
    ROUND(max_payment, 2) AS max_payment,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country_name, suspicion_rank;