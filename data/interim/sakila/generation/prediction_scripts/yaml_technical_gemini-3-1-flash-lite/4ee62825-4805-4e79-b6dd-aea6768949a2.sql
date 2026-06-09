WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(TIME(p.p06)) AS min_time,
        MAX(TIME(p.p06)) AS max_time
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        ds.*,
        (
            SELECT AVG(ds2.total_amount)
            FROM daily_stats AS ds2
            WHERE ds2.customer_id = ds.customer_id
              AND ds2.payment_date >= DATE(ds.payment_date, '-30 days')
              AND ds2.payment_date < ds.payment_date
        ) AS avg_prev_30d
    FROM daily_stats AS ds
),
country_percentiles AS (
    SELECT
        ct.d03 AS country_id,
        MAX(ds.total_amount) AS p95_threshold
    FROM daily_stats AS ds
    JOIN cus AS c ON c.h01 = ds.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    GROUP BY ct.d03
    HAVING COUNT(*) >= 20 -- Упрощенный расчет перцентиля
),
suspicious_days AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city_name,
        cn.c02 AS country_name,
        cn.c01 AS country_id,
        (ch.total_amount / NULLIF(ch.avg_prev_30d, 0)) AS exceed_ratio
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN country_percentiles AS cp ON cp.country_id = cn.c01
    WHERE c.h07 = 'Y'
      AND ch.payment_count >= 3
      AND ch.staff_count >= 2
      AND ch.avg_prev_30d > 0
      AND ch.total_amount >= 3 * ch.avg_prev_30d
      AND ch.total_amount > cp.p95_threshold
)
SELECT
    customer_name,
    city_name,
    country_name,
    payment_date,
    payment_count,
    ROUND(total_amount, 2) AS total_amount,
    staff_count,
    store_count,
    min_time,
    max_time,
    ROUND(max_payment, 2) AS max_payment,
    RANK() OVER (PARTITION BY country_id ORDER BY exceed_ratio DESC) AS suspicion_rank
FROM suspicious_days
ORDER BY country_name, suspicion_rank;