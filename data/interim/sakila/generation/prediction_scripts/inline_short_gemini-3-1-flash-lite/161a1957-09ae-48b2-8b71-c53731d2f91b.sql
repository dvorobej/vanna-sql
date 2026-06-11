WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_history AS (
    SELECT
        ds.*,
        (
            SELECT AVG(h.daily_amount)
            FROM daily_stats AS h
            WHERE h.customer_id = ds.customer_id
              AND h.payment_date >= date(ds.payment_date, '-30 days')
              AND h.payment_date < ds.payment_date
        ) AS avg_30d
    FROM daily_stats AS ds
    WHERE ds.payment_count >= 3
      AND (ds.staff_count > 1 OR ds.store_count > 1)
),
country_percentiles AS (
    SELECT
        c.c01 AS country_id,
        (SELECT val FROM (
            SELECT daily_amount AS val
            FROM daily_stats ds2
            JOIN cus c2 ON c2.h01 = ds2.customer_id
            JOIN adr a ON a.e01 = c2.h06
            JOIN cty ct ON ct.d01 = a.e05
            WHERE ct.d03 = c.c01
            ORDER BY val
            LIMIT 1 OFFSET (SELECT COUNT(*) * 0.95 FROM daily_stats)
        )) AS p95_val
    FROM cnt c
),
suspicious_data AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        (ch.daily_amount - ch.avg_30d) AS deviation
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    JOIN country_percentiles AS cp ON cp.country_id = cnt.c01
    WHERE ch.avg_30d IS NOT NULL
      AND ch.daily_amount >= 2 * ch.avg_30d
      AND ch.daily_amount > cp.p95_val
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    staff_count,
    ROUND(deviation, 2) AS deviation,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_data
ORDER BY country, suspicion_rank;