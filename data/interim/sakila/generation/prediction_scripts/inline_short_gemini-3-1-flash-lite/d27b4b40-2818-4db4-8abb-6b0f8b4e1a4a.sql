WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
daily_with_avg AS (
    SELECT
        dp.*,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS avg_prev_30
    FROM daily_payments AS dp
),
suspicious_days AS (
    SELECT
        dwa.*,
        (dwa.daily_sum / NULLIF(dwa.avg_prev_30, 0)) AS excess_ratio,
        RANK() OVER (PARTITION BY dwa.customer_id ORDER BY dwa.daily_sum DESC) AS day_rank_for_customer
    FROM daily_with_avg AS dwa
    WHERE dwa.avg_prev_30 > 0
      AND dwa.daily_sum >= 3 * dwa.avg_prev_30
      AND dwa.payment_count >= 3
      AND (dwa.staff_count > 1 OR dwa.store_count > 1)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.daily_sum, 2) AS daily_sum,
    ROUND(sd.avg_prev_30, 2) AS avg_prev_30,
    ROUND(sd.excess_ratio, 2) AS excess_ratio,
    sd.day_rank_for_customer
FROM suspicious_days AS sd
JOIN cus AS c ON c.h01 = sd.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY sd.excess_ratio DESC, sd.daily_sum DESC;