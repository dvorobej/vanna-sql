WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_op_time,
        MAX(p.p06) AS last_op_time,
        MAX(CAST(p.p05 AS REAL)) AS max_payment
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        ds.*,
        (
            SELECT SUM(ds2.day_amount) / 30.0
            FROM daily_stats AS ds2
            WHERE ds2.customer_id = ds.customer_id
              AND ds2.payment_date >= DATE(ds.payment_date, '-30 days')
              AND ds2.payment_date < ds.payment_date
        ) AS avg_prev_30d
    FROM daily_stats AS ds
    WHERE ds.payment_count >= 3
      AND ds.staff_count >= 2
),
country_percentiles AS (
    SELECT
        c.c01 AS country_id,
        (SELECT val FROM (
            SELECT day_amount AS val, PERCENT_RANK() OVER (ORDER BY day_amount) AS pr
            FROM daily_stats ds2
            JOIN cus c2 ON c2.h01 = ds2.customer_id
            JOIN adr a2 ON a2.e01 = c2.h06
            JOIN cty ct2 ON ct2.d01 = a2.e05
            WHERE ct2.d03 = c.c01
        ) WHERE pr >= 0.95 LIMIT 1) AS p95_amount
    FROM cnt c
),
suspicious_cases AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city_name,
        cnt.c02 AS country_name,
        cnt.c01 AS country_id,
        (ch.day_amount / NULLIF(ch.avg_prev_30d, 0)) AS exceed_ratio
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = ct.d03
    JOIN country_percentiles AS cp ON cp.country_id = cnt.c01
    WHERE ch.avg_prev_30d > 0
      AND ch.day_amount > (3 * ch.avg_prev_30d)
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
    first_op_time,
    last_op_time,
    ROUND(max_payment, 2) AS max_payment,
    RANK() OVER (PARTITION BY country_id ORDER BY exceed_ratio DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country_name, suspicion_rank;