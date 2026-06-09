WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        d.*,
        (
            SELECT AVG(dh.day_amount)
            FROM daily_payments AS dh
            WHERE dh.customer_id = d.customer_id
              AND dh.payment_date >= date(d.payment_date, '-30 days')
              AND dh.payment_date < d.payment_date
        ) AS avg_daily_amount_prev_30
    FROM daily_payments AS d
),
suspicious_days AS (
    SELECT
        dwh.*,
        dwh.day_amount - dwh.avg_daily_amount_prev_30 AS excess_amount
    FROM daily_with_history AS dwh
    WHERE dwh.avg_daily_amount_prev_30 IS NOT NULL
      AND dwh.avg_daily_amount_prev_30 > 0
      AND dwh.day_amount >= 3.0 * dwh.avg_daily_amount_prev_30
      AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
)
SELECT
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    sd.payment_date AS suspicious_date,
    ROUND(sd.day_amount, 2) AS day_amount,
    sd.payment_count,
    sd.distinct_staff_count AS staff_count_distinct,
    ROUND(sd.avg_daily_amount_prev_30, 2) AS avg_daily_amount_prev_30,
    RANK() OVER (
        ORDER BY sd.excess_amount DESC, sd.day_amount DESC, cg.country_name, cg.city_name
    ) AS suspicion_rank
FROM suspicious_days AS sd
JOIN customer_geo AS cg ON cg.customer_id = sd.customer_id
ORDER BY
    suspicion_rank,
    sd.payment_date,
    cg.last_name,
    cg.first_name;