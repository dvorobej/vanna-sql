WITH day_payments AS (
    SELECT
        p.p02 AS customer_id,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s1.o07) AS store_count
    FROM pay p
    JOIN stf s1 ON s1.o01 = p.p03
    WHERE p.p06 IS NOT NULL
    GROUP BY
        p.p02,
        date(p.p06)
),
day_with_prev_avg AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp2.day_amount)
            FROM day_payments dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= date(dp.payment_date, '-30 days')
              AND dp2.payment_date < dp.payment_date
        ) AS avg_prev_30d_day_amount
    FROM day_payments dp
),
suspicious_days AS (
    SELECT
        dwp.*,
        dwp.day_amount / NULLIF(dwp.avg_prev_30d_day_amount, 0) AS exceed_ratio
    FROM day_with_prev_avg dwp
    WHERE dwp.avg_prev_30d_day_amount IS NOT NULL
      AND dwp.avg_prev_30d_day_amount > 0
      AND dwp.day_amount >= 3.0 * dwp.avg_prev_30d_day_amount
      AND dwp.payment_count >= 3
      AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
)
SELECT
    sd.customer_id,
    cg.country_name AS country,
    cg.city_name AS city,
    sd.payment_date AS suspicious_date,
    sd.payment_count AS payments_count,
    ROUND(sd.day_amount, 2) AS day_total_amount,
    ROUND(sd.avg_prev_30d_day_amount, 2) AS avg_daily_amount_prev_30d,
    ROUND(sd.exceed_ratio, 4) AS exceed_coefficient,
    RANK() OVER (
        PARTITION BY sd.customer_id
        ORDER BY sd.day_amount DESC
    ) AS day_suspicion_rank
FROM suspicious_days sd
JOIN customer_geo cg
    ON cg.customer_id = sd.customer_id
ORDER BY
    sd.customer_id,
    day_suspicion_rank,
    sd.payment_date;