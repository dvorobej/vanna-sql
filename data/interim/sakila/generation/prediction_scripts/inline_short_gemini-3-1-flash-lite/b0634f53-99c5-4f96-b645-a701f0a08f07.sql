WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MAX(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) AS has_other_store_payment
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, DATE(p.p06)
),
scored_days AS (
    SELECT
        dp.*,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_day >= DATE(dp.payment_day, '-30 days')
              AND prev.payment_day < dp.payment_day
        ) AS avg_30d
    FROM daily_payments AS dp
),
suspicious_days AS (
    SELECT
        sd.*,
        (sd.day_amount / NULLIF(sd.avg_30d, 0)) AS exceed_ratio
    FROM scored_days AS sd
    JOIN cus AS c ON c.h01 = sd.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    WHERE sd.payment_count >= 3
      AND sd.day_amount >= 2.0 * sd.avg_30d
      AND sd.staff_count >= 2
      AND sd.store_count >= 2
      AND sd.has_other_store_payment = 1
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country,
    ci.d02 AS city,
    sd.payment_day,
    sd.payment_count,
    ROUND(sd.day_amount, 2) AS day_amount,
    ROUND(sd.exceed_ratio, 2) AS exceed_ratio,
    RANK() OVER (PARTITION BY co.c01 ORDER BY sd.exceed_ratio DESC) AS country_rank
FROM suspicious_days AS sd
JOIN cus AS c ON c.h01 = sd.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty AS ci ON ci.d01 = a.e05
JOIN cnt AS co ON co.c01 = ci.d03
ORDER BY co.c02, country_rank;