WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
daily_with_avg AS (
    SELECT
        ds.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.payment_date >= DATE(ds.payment_date, '-30 days')
              AND prev.payment_date < ds.payment_date
        ) AS avg_prev_30
    FROM daily_stats AS ds
),
suspicious_days AS (
    SELECT
        dwa.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        (dwa.daily_amount / NULLIF(dwa.avg_prev_30, 0)) AS spike_ratio
    FROM daily_with_avg AS dwa
    JOIN cus AS c ON c.h01 = dwa.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    WHERE dwa.avg_prev_30 > 0
      AND dwa.daily_amount >= 3 * dwa.avg_prev_30
      AND (dwa.staff_count >= 2 OR dwa.store_count >= 2)
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    ROUND(daily_amount, 2) AS daily_amount,
    payment_count,
    staff_count,
    RANK() OVER (ORDER BY spike_ratio DESC) AS suspicion_rank
FROM suspicious_days
ORDER BY suspicion_rank;