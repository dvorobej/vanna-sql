WITH payment_base AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS store_id
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
),
daily_customer AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        COUNT(*) AS payment_count,
        SUM(pb.amount) AS daily_amount,
        COUNT(DISTINCT pb.staff_id) AS staff_count,
        COUNT(DISTINCT pb.store_id) AS store_count
    FROM payment_base AS pb
    GROUP BY pb.customer_id, pb.payment_day
),
daily_history AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc2.daily_amount)
            FROM daily_customer AS dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_day >= DATE(dc.payment_day, '-30 day')
              AND dc2.payment_day < dc.payment_day
        ) AS avg_30d_daily_amount
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        dh.customer_id,
        dh.payment_day,
        dh.payment_count,
        dh.daily_amount,
        dh.avg_30d_daily_amount,
        dh.staff_count,
        dh.store_count,
        dh.daily_amount - dh.avg_30d_daily_amount AS deviation_from_avg_30d
    FROM daily_history AS dh
    WHERE dh.payment_count >= 3
      AND dh.avg_30d_daily_amount IS NOT NULL
      AND dh.daily_amount >= dh.avg_30d_daily_amount * 3
      AND (dh.staff_count > 1 OR dh.store_count > 1)
)
SELECT
    cn.c02 AS country,
    ct.d02 AS city,
    sd.payment_day,
    sd.payment_count,
    ROUND(sd.daily_amount, 2) AS daily_amount,
    ROUND(sd.avg_30d_daily_amount, 2) AS avg_30d_daily_amount,
    ROUND(sd.deviation_from_avg_30d, 2) AS deviation_from_avg_30d,
    sd.staff_count,
    sd.store_count,
    RANK() OVER (
        PARTITION BY cn.c01
        ORDER BY sd.deviation_from_avg_30d DESC
    ) AS risk_rank
FROM suspicious_days AS sd
JOIN cus AS cu
    ON cu.h01 = sd.customer_id
JOIN adr AS a
    ON a.e01 = cu.h06
JOIN cty AS ct
    ON ct.d01 = a.e05
JOIN cnt AS cn
    ON cn.c01 = ct.d03
ORDER BY
    risk_rank,
    cn.c02,
    ct.d02,
    sd.payment_day;