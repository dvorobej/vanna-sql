WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_op_time,
        MAX(p.p06) AS last_op_time
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
),
country_percentiles AS (
    SELECT
        c.c01 AS country_id,
        (
            SELECT val FROM (
                SELECT day_amount AS val, PERCENT_RANK() OVER (ORDER BY day_amount) AS pr
                FROM daily_stats ds2
                JOIN cus c2 ON c2.h01 = ds2.customer_id
                JOIN adr a ON a.e01 = c2.h06
                JOIN cty ct ON ct.d01 = a.e05
                WHERE ct.d03 = c.c01
            ) WHERE pr >= 0.95 LIMIT 1
        ) AS p95_amount
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
    FROM customer_history ch
    JOIN cus c ON c.h01 = ch.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cnt ON cnt.c01 = ct.d03
    JOIN country_percentiles cp ON cp.country_id = cnt.c01
    WHERE ch.payment_count >= 3
      AND ch.staff_count >= 2
      AND ch.day_amount > (3.0 * ch.avg_prev_30d)
      AND ch.day_amount > cp.p95_amount
)
SELECT
    customer_name,
    city_name,
    country_name,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS total_amount,
    staff_count,
    store_count,
    first_op_time,
    last_op_time,
    ROUND(max_payment, 2) AS max_payment,
    RANK() OVER (PARTITION BY country_id ORDER BY exceed_ratio DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country_name, suspicion_rank;