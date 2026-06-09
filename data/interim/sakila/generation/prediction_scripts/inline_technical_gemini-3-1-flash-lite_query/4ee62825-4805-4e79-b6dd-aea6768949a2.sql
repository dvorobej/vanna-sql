WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        MAX(p.p05) AS max_payment,
        MIN(p.p06) AS first_payment_time,
        MAX(p.p06) AS last_payment_time,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        c.h06 AS address_id
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN cus AS c ON c.h01 = p.p02
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
daily_with_baseline AS (
    SELECT
        ds.*,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        cg.country_id,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.payment_date >= DATE(ds.payment_date, '-30 day')
              AND prev.payment_date < ds.payment_date
        ) AS avg_prev_30d
    FROM daily_stats AS ds
    JOIN customer_geo AS cg ON cg.customer_id = ds.customer_id
),
country_p95 AS (
    SELECT
        country_id,
        MAX(day_amount) AS p95_val
    FROM (
        SELECT
            country_id,
            day_amount,
            PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) as pr
        FROM daily_with_baseline
    )
    WHERE pr <= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        dwb.*,
        (dwb.day_amount / NULLIF(dwb.avg_prev_30d, 0)) AS exceed_ratio
    FROM daily_with_baseline AS dwb
    JOIN country_p95 AS cp ON cp.country_id = dwb.country_id
    WHERE dwb.payment_count >= 3
      AND dwb.staff_count >= 2
      AND dwb.day_amount > (3.0 * dwb.avg_prev_30d)
      AND dwb.day_amount > cp.p95_val
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
    first_payment_time,
    last_payment_time,
    max_payment,
    RANK() OVER (PARTITION BY country_id ORDER BY exceed_ratio DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country_name, suspicion_rank;