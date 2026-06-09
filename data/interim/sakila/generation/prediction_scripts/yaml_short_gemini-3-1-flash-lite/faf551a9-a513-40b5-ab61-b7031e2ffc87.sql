WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(p.p01) AS payment_count,
        c.h02 AS store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        c.h03 AS first_name,
        c.h04 AS last_name
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    GROUP BY p.p02, DATE(p.p06)
),
daily_stats AS (
    SELECT
        dcp.*,
        (
            SELECT AVG(dcp2.day_amount)
            FROM daily_customer_payments AS dcp2
            WHERE dcp2.customer_id = dcp.customer_id
              AND dcp2.payment_date >= DATE(dcp.payment_date, '-30 days')
              AND dcp2.payment_date < dcp.payment_date
        ) AS avg_30d
    FROM daily_customer_payments AS dcp
),
country_p95 AS (
    SELECT
        country_id,
        MAX(day_amount) AS p95_val
    FROM (
        SELECT
            country_id,
            day_amount,
            PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) as pr
        FROM daily_customer_payments
    )
    WHERE pr <= 0.95
    GROUP BY country_id
),
suspicious_days AS (
    SELECT
        ds.*,
        cp.p95_val,
        (ds.day_amount - ds.avg_30d) AS deviation
    FROM daily_stats AS ds
    JOIN country_p95 AS cp ON ds.country_id = cp.country_id
    WHERE ds.avg_30d > 0
      AND ds.day_amount >= (ds.avg_30d * 3)
      AND ds.day_amount >= cp.p95_val
)
SELECT
    payment_date,
    first_name,
    last_name,
    country_name,
    city_name,
    store_id,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_30d, 2) AS avg_30d,
    ROUND(deviation, 2) AS deviation,
    RANK() OVER (ORDER BY day_amount DESC) AS spike_rank
FROM suspicious_days
ORDER BY spike_rank;