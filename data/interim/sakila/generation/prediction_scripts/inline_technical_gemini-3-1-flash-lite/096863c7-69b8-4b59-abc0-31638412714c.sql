WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_stats AS (
    SELECT
        dcp.*,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        (
            SELECT AVG(dcp2.daily_amount)
            FROM daily_customer_payments AS dcp2
            WHERE dcp2.customer_id = dcp.customer_id
              AND dcp2.payment_date >= DATE(dcp.payment_date, '-30 days')
              AND dcp2.payment_date < dcp.payment_date
        ) AS personal_avg_30d,
        (
            SELECT AVG(dcp3.daily_amount)
            FROM daily_customer_payments AS dcp3
            JOIN customer_geo AS cg3 ON cg3.customer_id = dcp3.customer_id
            WHERE cg3.country_id = cg.country_id
              AND dcp3.payment_date = dcp.payment_date
        ) AS country_avg_daily
    FROM daily_customer_payments AS dcp
    JOIN customer_geo AS cg ON cg.customer_id = dcp.customer_id
),
suspicious_days AS (
    SELECT
        *,
        daily_amount - personal_avg_30d AS dev_personal,
        daily_amount - country_avg_daily AS dev_country
    FROM daily_stats
    WHERE personal_avg_30d > 0
      AND daily_amount > 3 * personal_avg_30d
      AND daily_amount > country_avg_daily
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_date,
    ROUND(daily_amount, 2) AS daily_amount,
    payment_count,
    ROUND(dev_personal, 2) AS deviation_from_personal_avg,
    ROUND(dev_country, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY daily_amount DESC
    ) AS country_rank
FROM suspicious_days
ORDER BY country_name, country_rank, payment_date;