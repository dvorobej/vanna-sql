WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        MAX(s.o07) AS store_id
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_with_avg AS (
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
country_percentiles AS (
    SELECT
        cg.country_id,
        MAX(CASE WHEN rn <= 0.95 * total_count THEN day_amount END) AS p95_day_amount
    FROM (
        SELECT
            dcp.day_amount,
            cg.country_id,
            ROW_NUMBER() OVER (PARTITION BY cg.country_id ORDER BY dcp.day_amount) AS rn,
            COUNT(*) OVER (PARTITION BY cg.country_id) AS total_count
        FROM daily_customer_payments AS dcp
        JOIN customer_geo AS cg ON cg.customer_id = dcp.customer_id
    )
    GROUP BY country_id
),
suspicious_days AS (
    SELECT
        dwa.*,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        cp.p95_day_amount
    FROM daily_with_avg AS dwa
    JOIN customer_geo AS cg ON cg.customer_id = dwa.customer_id
    JOIN country_percentiles AS cp ON cp.country_id = cg.country_id
    WHERE dwa.avg_30d > 0
      AND dwa.day_amount >= 3 * dwa.avg_30d
      AND dwa.day_amount > cp.p95_day_amount
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
    ROUND(day_amount - avg_30d, 2) AS deviation,
    RANK() OVER (PARTITION BY country_name ORDER BY day_amount DESC) AS country_rank
FROM suspicious_days
ORDER BY country_name, country_rank;