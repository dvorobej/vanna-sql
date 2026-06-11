WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
daily_with_avg AS (
    SELECT
        ds.*,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.pay_date >= date(ds.pay_date, '-30 days')
              AND prev.pay_date < ds.pay_date
        ) AS avg_30d
    FROM daily_stats AS ds
),
country_p95 AS (
    SELECT
        cty.d03 AS country_id,
        (SELECT val FROM (
            SELECT CAST(daily_sum AS REAL) AS val
            FROM daily_stats ds2
            JOIN cus c ON c.h01 = ds2.customer_id
            JOIN adr a ON a.e01 = c.h06
            JOIN cty ON cty.d01 = a.e05
            WHERE cty.d03 = cnt.c01
            ORDER BY val
            LIMIT 1 OFFSET (SELECT COUNT(*) * 0.95 FROM daily_stats)
        )) AS p95_val
    FROM cnt
),
suspicious_data AS (
    SELECT
        dwa.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        (dwa.daily_sum - dwa.avg_30d) AS deviation
    FROM daily_with_avg AS dwa
    JOIN cus AS c ON c.h01 = dwa.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN country_p95 AS cp ON cp.country_id = cnt.c01
    WHERE dwa.payment_count >= 3
      AND (dwa.staff_count > 1 OR dwa.store_count > 1)
      AND dwa.avg_30d > 0
      AND dwa.daily_sum >= 2 * dwa.avg_30d
      AND dwa.daily_sum > cp.p95_val
)
SELECT
    customer_name,
    country,
    city,
    pay_date,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    staff_count,
    ROUND(deviation, 2) AS deviation,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_data
ORDER BY suspicion_rank, country, pay_date;