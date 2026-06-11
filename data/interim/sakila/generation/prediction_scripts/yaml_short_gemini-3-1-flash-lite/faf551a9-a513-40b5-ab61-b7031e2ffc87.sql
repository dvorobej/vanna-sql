WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
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
country_percentiles AS (
    SELECT
        country_id,
        MAX(day_amount) AS p95_threshold
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
daily_with_baseline AS (
    SELECT
        dcp.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_customer_payments AS prev
            WHERE prev.customer_id = dcp.customer_id
              AND prev.payment_date >= DATE(dcp.payment_date, '-30 days')
              AND prev.payment_date < dcp.payment_date
        ) AS avg_30d
    FROM daily_customer_payments AS dcp
),
suspicious_events AS (
    SELECT
        dwb.*,
        cp.p95_threshold,
        (dwb.day_amount - dwb.avg_30d) AS deviation
    FROM daily_with_baseline AS dwb
    JOIN country_percentiles AS cp ON cp.country_id = dwb.country_id
    WHERE dwb.avg_30d > 0
      AND dwb.day_amount >= dwb.avg_30d * 3
      AND dwb.day_amount > cp.p95_threshold
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
    RANK() OVER (PARTITION BY country_id ORDER BY day_amount DESC) AS rank_in_country
FROM suspicious_events
ORDER BY country_name, rank_in_country;