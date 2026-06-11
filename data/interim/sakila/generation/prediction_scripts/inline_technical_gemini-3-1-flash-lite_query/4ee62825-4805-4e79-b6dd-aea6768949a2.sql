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
customer_history AS (
    SELECT
        ds.*,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.payment_date >= DATE(ds.payment_date, '-30 days')
              AND prev.payment_date < ds.payment_date
        ) AS avg_30d
    FROM daily_stats AS ds
    WHERE ds.payment_count >= 3
      AND ds.staff_count >= 2
),
country_percentiles AS (
    SELECT
        cty.d03 AS country_id,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ds.day_amount) AS p95_amount
    FROM daily_stats AS ds
    JOIN adr AS a ON a.e01 = ds.address_id
    JOIN cty ON cty.d01 = a.e05
    GROUP BY cty.d03
),
suspicious_cases AS (
    SELECT
        ch.*,
        cnt.c02 AS country_name,
        city.d02 AS city_name,
        (ch.day_amount / NULLIF(ch.avg_30d, 0)) AS exceed_ratio
    FROM customer_history AS ch
    JOIN adr AS a ON a.e01 = ch.address_id
    JOIN cty AS city ON city.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = city.d03
    JOIN country_percentiles AS cp ON cp.country_id = city.d03
    WHERE ch.day_amount > 3.0 * ch.avg_30d
      AND ch.day_amount > cp.p95_amount
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    sc.city_name,
    sc.country_name,
    sc.payment_date,
    sc.payment_count,
    sc.day_amount,
    sc.staff_count,
    sc.store_count,
    sc.first_payment_time,
    sc.last_payment_time,
    sc.max_payment,
    RANK() OVER (PARTITION BY sc.country_name ORDER BY sc.exceed_ratio DESC) AS suspicion_rank
FROM suspicious_cases AS sc
JOIN cus AS c ON c.h01 = sc.customer_id
ORDER BY sc.country_name, suspicion_rank;