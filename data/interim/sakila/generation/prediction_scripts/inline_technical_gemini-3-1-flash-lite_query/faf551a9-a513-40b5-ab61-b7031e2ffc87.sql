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
customer_stats AS (
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
        c.c01 AS country_id,
        (
            SELECT val
            FROM (
                SELECT day_amount AS val,
                       PERCENT_RANK() OVER (ORDER BY day_amount) AS pr
                FROM daily_customer_payments AS dcp2
                JOIN cus AS c2 ON c2.h01 = dcp2.customer_id
                JOIN adr AS a2 ON a2.e01 = c2.h06
                JOIN cty AS ci2 ON ci2.d01 = a2.e05
                WHERE ci2.d03 = c.c01
            )
            WHERE pr >= 0.95
            ORDER BY val ASC
            LIMIT 1
        ) AS p95_val
    FROM cnt AS c
),
suspicious_activity AS (
    SELECT
        cs.*,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        cp.p95_val
    FROM customer_stats AS cs
    JOIN cus AS c ON c.h01 = cs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    JOIN country_percentiles AS cp ON cp.country_id = co.c01
    WHERE cs.avg_30d > 0
      AND cs.day_amount >= 3 * cs.avg_30d
      AND cs.day_amount > cp.p95_val
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
FROM suspicious_activity
ORDER BY country_name, country_rank;