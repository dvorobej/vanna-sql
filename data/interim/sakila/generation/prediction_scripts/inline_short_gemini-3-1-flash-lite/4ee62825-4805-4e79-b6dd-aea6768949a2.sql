WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS day_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_op_time,
        MAX(p.p06) AS last_op_time,
        GROUP_CONCAT(DISTINCT s.o02 || ' ' || s.o03) AS staff_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        customer_id,
        AVG(day_amount) AS avg_day_amount
    FROM daily_stats
    GROUP BY customer_id
),
country_percentiles AS (
    SELECT
        cty.d03 AS country_id,
        MAX(day_amount) AS p95_threshold
    FROM (
        SELECT
            day_amount,
            country_id,
            PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) as pr
        FROM daily_stats ds
        JOIN cus c ON c.h01 = ds.customer_id
        JOIN adr a ON a.e01 = c.h06
        JOIN cty ON cty.d01 = a.e05
    ) WHERE pr >= 0.95
    GROUP BY country_id
),
suspicious_days AS (
    SELECT
        ds.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        ch.avg_day_amount,
        cp.p95_threshold
    FROM daily_stats ds
    JOIN cus c ON c.h01 = ds.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN customer_history ch ON ch.customer_id = ds.customer_id
    JOIN country_percentiles cp ON cp.country_id = cty.d03
    WHERE ds.payment_count >= 3
      AND ds.staff_count >= 2
      AND ds.day_amount > ch.avg_day_amount
      AND ds.day_amount > cp.p95_threshold
      AND c.h07 = 'Y'
)
SELECT
    customer_name,
    city_name,
    country_name,
    payment_date,
    day_amount,
    payment_count,
    staff_list,
    store_count,
    first_op_time,
    last_op_time,
    max_payment,
    RANK() OVER (PARTITION BY country_name ORDER BY day_amount DESC) AS suspicion_rank
FROM suspicious_days
ORDER BY suspicion_rank, day_amount DESC;