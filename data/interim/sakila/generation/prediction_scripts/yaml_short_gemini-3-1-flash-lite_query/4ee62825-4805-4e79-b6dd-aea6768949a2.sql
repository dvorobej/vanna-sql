WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_payment_time,
        MAX(p.p06) AS last_payment_time
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        ds.*,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.payment_date >= DATE(ds.payment_date, '-30 days')
              AND prev.payment_date < ds.payment_date
        ) AS avg_prev_30d
    FROM daily_stats AS ds
    WHERE ds.payment_count >= 3
      AND ds.staff_count >= 2
),
country_percentiles AS (
    SELECT
        c.c01 AS country_id,
        (
            SELECT val FROM (
                SELECT day_amount AS val, PERCENT_RANK() OVER (ORDER BY day_amount) AS pr
                FROM daily_stats AS ds2
                JOIN cus AS c2 ON c2.h01 = ds2.customer_id
                JOIN adr AS a2 ON a2.e01 = c2.h06
                JOIN cty AS ci2 ON ci2.d01 = a2.e05
                WHERE ci2.d03 = c.c01
            ) WHERE pr >= 0.95 LIMIT 1
        ) AS p95_amount
    FROM cnt AS c
),
suspicious_cases AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city_name,
        cn.c02 AS country_name,
        (ch.day_amount / NULLIF(ch.avg_prev_30d, 0)) AS exceed_ratio
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN country_percentiles AS cp ON cp.country_id = cn.c01
    WHERE ch.day_amount > 3.0 * ch.avg_prev_30d
      AND ch.day_amount > cp.p95_amount
)
SELECT
    customer_name,
    city_name,
    country_name,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_count,
    store_count,
    first_payment_time,
    last_payment_time,
    ROUND(max_payment, 2) AS max_payment,
    RANK() OVER (PARTITION BY country_name ORDER BY exceed_ratio DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country_name, suspicion_rank;