WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        c.h02 AS store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        c.h03 AS first_name,
        c.h04 AS last_name
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    GROUP BY p.p02, DATE(p.p06)
),
daily_with_avg AS (
    SELECT
        dcp.*,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_customer_payments AS prev
            WHERE prev.customer_id = dcp.customer_id
              AND prev.payment_date >= DATE(dcp.payment_date, '-30 days')
              AND prev.payment_date < dcp.payment_date
        ) AS avg_30d
    FROM daily_customer_payments AS dcp
),
country_percentiles AS (
    SELECT
        country_id,
        MAX(day_amount) AS p95_threshold
    FROM (
        SELECT
            country_id,
            day_amount,
            PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) AS pr
        FROM daily_customer_payments
    )
    WHERE pr <= 0.95
    GROUP BY country_id
),
suspicious_events AS (
    SELECT
        dwa.*,
        cp.p95_threshold,
        (dwa.day_amount - dwa.avg_30d) AS deviation
    FROM daily_with_avg AS dwa
    JOIN country_percentiles AS cp ON cp.country_id = dwa.country_id
    WHERE dwa.avg_30d > 0
      AND dwa.day_amount >= 3 * dwa.avg_30d
      AND dwa.day_amount > cp.p95_threshold
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
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS country_rank
FROM suspicious_events
ORDER BY country_name, country_rank;