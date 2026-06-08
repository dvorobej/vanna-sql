WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_payment_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(i.n03, s.o07)) AS store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    GROUP BY
        p.p02,
        date(p.p06)
),
scored_days AS (
    SELECT
        dp.customer_id,
        dp.payment_date,
        dp.day_payment_amount,
        dp.payment_count,
        dp.staff_count,
        dp.store_count,
        COALESCE((
            SELECT SUM(CAST(p2.p05 AS REAL))
            FROM pay AS p2
            WHERE p2.p02 = dp.customer_id
              AND date(p2.p06) >= date(dp.payment_date, '-30 days')
              AND date(p2.p06) < dp.payment_date
        ), 0.0) / 30.0 AS avg_daily_amount_prev_30_days
    FROM daily_payments AS dp
),
suspicious_days AS (
    SELECT
        sd.*,
        sd.day_payment_amount / sd.avg_daily_amount_prev_30_days AS suspicious_ratio
    FROM scored_days AS sd
    WHERE sd.avg_daily_amount_prev_30_days > 0
      AND sd.day_payment_amount >= 3 * sd.avg_daily_amount_prev_30_days
      AND (sd.staff_count > 1 OR sd.store_count > 1)
),
ranked_suspicious_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            ORDER BY
                sd.suspicious_ratio DESC,
                sd.day_payment_amount DESC,
                sd.customer_id,
                sd.payment_date
        ) AS suspicious_rank
    FROM suspicious_days AS sd
)
SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    rsd.payment_date AS suspicious_activity_date,
    ROUND(rsd.day_payment_amount, 2) AS day_payment_amount,
    rsd.payment_count,
    rsd.staff_count,
    ROUND(rsd.avg_daily_amount_prev_30_days, 2) AS avg_daily_amount_prev_30_days,
    rsd.suspicious_rank
FROM ranked_suspicious_days AS rsd
JOIN cus AS c
    ON c.h01 = rsd.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty
    ON cty.d01 = a.e05
JOIN cnt
    ON cnt.c01 = cty.d03
ORDER BY
    rsd.suspicious_rank,
    rsd.payment_date,
    c.h01;