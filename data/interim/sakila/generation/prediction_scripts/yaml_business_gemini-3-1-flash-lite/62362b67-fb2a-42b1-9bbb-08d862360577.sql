WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM pay AS p
    JOIN stf ON stf.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
historical_avg AS (
    SELECT
        da.customer_id,
        da.payment_date,
        da.daily_amount,
        da.payment_count,
        da.staff_count,
        da.store_count,
        (
            SELECT AVG(da2.daily_amount)
            FROM daily_activity AS da2
            WHERE da2.customer_id = da.customer_id
              AND da2.payment_date >= DATE(da.payment_date, '-30 days')
              AND da2.payment_date < da.payment_date
        ) AS avg_prev_30d
    FROM daily_activity AS da
    WHERE da.staff_count > 1 OR da.store_count > 1
),
suspicious_days AS (
    SELECT
        ha.*,
        (ha.daily_amount / NULLIF(ha.avg_prev_30d, 0)) AS excess_ratio
    FROM historical_avg AS ha
    WHERE ha.avg_prev_30d > 0
      AND ha.daily_amount > (ha.avg_prev_30d * 2)
)
SELECT
    sd.payment_date,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.daily_amount,
    sd.payment_count,
    sd.staff_count,
    ROUND(sd.avg_prev_30d, 2) AS avg_prev_30d,
    RANK() OVER (ORDER BY sd.excess_ratio DESC) AS suspicion_rank
FROM suspicious_days AS sd
JOIN cus AS c ON c.h01 = sd.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY suspicion_rank ASC;