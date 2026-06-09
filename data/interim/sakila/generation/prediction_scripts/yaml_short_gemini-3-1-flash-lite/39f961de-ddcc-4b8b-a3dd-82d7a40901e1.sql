WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        SUM(CASE WHEN f.i11 IN ('R', 'NC-17') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS restricted_rating_share
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN flm AS f ON f.i01 = i.n02
    GROUP BY p.p02, date(p.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.pay_date >= date(dp.pay_date, '-30 days')
              AND prev.pay_date < dp.pay_date
        ) AS avg_prev_30
    FROM daily_payments AS dp
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
suspicious_days AS (
    SELECT
        dwh.*,
        cg.city,
        cg.country,
        cg.country_id
    FROM daily_with_history AS dwh
    JOIN customer_geo AS cg ON cg.customer_id = dwh.customer_id
    WHERE dwh.avg_prev_30 > 0
      AND dwh.daily_sum >= 3 * dwh.avg_prev_30
      AND (dwh.staff_count >= 3 OR dwh.store_count >= 3)
)
SELECT
    city,
    country,
    pay_date,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(restricted_rating_share, 4) AS restricted_rating_share,
    RANK() OVER (
        PARTITION BY country_id, pay_date
        ORDER BY daily_sum DESC
    ) AS country_day_rank
FROM suspicious_days
ORDER BY
    country,
    pay_date,
    country_day_rank;