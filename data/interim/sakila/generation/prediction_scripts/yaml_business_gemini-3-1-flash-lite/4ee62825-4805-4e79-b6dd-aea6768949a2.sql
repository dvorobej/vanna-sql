WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS activity_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_payment_time,
        MAX(p.p06) AS last_payment_time,
        MAX(p.p05) AS max_payment
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
),
daily_stats AS (
    SELECT
        da.*,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_activity AS prev
            WHERE prev.customer_id = da.customer_id
              AND prev.activity_date >= date(da.activity_date, '-30 day')
              AND prev.activity_date < da.activity_date
        ) AS avg_30d_amount
    FROM daily_activity AS da
    JOIN customer_geo AS cg ON cg.customer_id = da.customer_id
    WHERE da.payment_count >= 3 AND da.staff_count >= 2
),
country_p95 AS (
    SELECT
        country_id,
        MAX(day_amount) AS p95_threshold
    FROM (
        SELECT
            cg.country_id,
            da.day_amount,
            PERCENT_RANK() OVER (PARTITION BY cg.country_id ORDER BY da.day_amount) AS p_rank
        FROM daily_activity AS da
        JOIN customer_geo AS cg ON cg.customer_id = da.customer_id
    )
    WHERE p_rank <= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        ds.*,
        (ds.day_amount - ds.avg_30d_amount) AS deviation
    FROM daily_stats AS ds
    JOIN country_p95 AS cp ON cp.country_id = ds.country_id
    WHERE ds.day_amount > ds.avg_30d_amount * 2
      AND ds.day_amount > cp.p95_threshold
)
SELECT
    customer_name,
    country_name,
    city_name,
    activity_date,
    payment_count,
    ROUND(day_amount, 2) AS total_amount,
    staff_count,
    store_count,
    first_payment_time,
    last_payment_time,
    ROUND(max_payment, 2) AS max_payment,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank_in_country
FROM suspicious_cases
ORDER BY country_name, suspicion_rank_in_country;