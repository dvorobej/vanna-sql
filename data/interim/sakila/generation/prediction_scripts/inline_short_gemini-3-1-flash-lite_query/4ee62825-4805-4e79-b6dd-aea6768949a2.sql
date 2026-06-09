WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_op_time,
        MAX(p.p06) AS last_op_time
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city_name,
        cnt.c02 AS country_name,
        cnt.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_with_history AS (
    SELECT
        ds.*,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        cg.country_id,
        (
            SELECT SUM(ds2.day_amount) / 30.0
            FROM daily_stats AS ds2
            WHERE ds2.customer_id = ds.customer_id
              AND ds2.payment_date >= DATE(ds.payment_date, '-30 days')
              AND ds2.payment_date < ds.payment_date
        ) AS avg_prev_30d
    FROM daily_stats AS ds
    JOIN customer_geo AS cg ON cg.customer_id = ds.customer_id
),
country_p95 AS (
    SELECT country_id,
           MAX(day_amount) AS p95_val
    FROM (
        SELECT country_id, day_amount,
               PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) as pr
        FROM daily_stats ds
        JOIN customer_geo cg ON cg.customer_id = ds.customer_id
    ) WHERE pr <= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        dwh.*,
        (dwh.day_amount / NULLIF(dwh.avg_prev_30d, 0)) AS exceed_ratio
    FROM daily_with_history AS dwh
    JOIN country_p95 AS cp ON cp.country_id = dwh.country_id
    WHERE dwh.payment_count >= 3
      AND dwh.staff_count >= 2
      AND dwh.day_amount > 3.0 * dwh.avg_prev_30d
      AND dwh.day_amount > cp.p95_val
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