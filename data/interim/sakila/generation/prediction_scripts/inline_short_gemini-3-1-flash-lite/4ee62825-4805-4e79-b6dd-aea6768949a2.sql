WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_op_time,
        MAX(p.p06) AS last_op_time,
        MAX(p.p05) AS max_payment,
        GROUP_CONCAT(DISTINCT s.o02 || ' ' || s.o03) AS staff_names
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
        -- SQLite не имеет встроенной функции PERCENTILE, используем метод ранжирования
        val AS p95_val
    FROM (
        SELECT
            cnt.c01 AS country_id,
            ds.day_amount AS val,
            PERCENT_RANK() OVER (PARTITION BY cnt.c01 ORDER BY ds.day_amount) AS pr
        FROM daily_stats AS ds
        JOIN cus AS c ON c.h01 = ds.customer_id
        JOIN adr AS a ON a.e01 = c.h06
        JOIN cty ON cty.d01 = a.e05
        JOIN cnt ON cnt.c01 = cty.d03
    )
    WHERE pr >= 0.95
    GROUP BY country_id
),
suspicious_days AS (
    SELECT
        ds.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city_name,
        cnt.c02 AS country_name,
        ch.avg_day_amount,
        cp.p95_val
    FROM daily_stats AS ds
    JOIN cus AS c ON c.h01 = ds.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN customer_history AS ch ON ch.customer_id = ds.customer_id
    JOIN country_percentiles AS cp ON cp.country_id = cnt.c01
    WHERE ds.payment_count >= 3
      AND ds.staff_count >= 2
      AND ds.day_amount > ch.avg_day_amount
      AND ds.day_amount > cp.p95_val
      AND c.h07 = 'Y'
)
SELECT
    customer_name,
    city_name,
    country_name,
    payment_date,
    day_amount,
    payment_count,
    staff_count,
    store_count,
    staff_names,
    first_op_time,
    last_op_time,
    max_payment,
    RANK() OVER (ORDER BY day_amount DESC) AS suspicion_rank
FROM suspicious_days
ORDER BY suspicion_rank;