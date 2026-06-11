WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(i.n03, s.o07)) AS store_count,
        SUM(CASE WHEN f.i11 IN ('R', 'NC-17') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS r_nc17_share
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
            SELECT AVG(prev.day_amount)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS avg_prev_30d
    FROM daily_payments AS dp
),
suspicious_days AS (
    SELECT
        dwh.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id
    FROM daily_with_history AS dwh
    JOIN cus AS c ON c.h01 = dwh.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE dwh.avg_prev_30d > 0
      AND dwh.day_amount >= 3 * dwh.avg_prev_30d
      AND (dwh.staff_count > 1 OR dwh.store_count > 1)
      AND dwh.payment_count >= 3
),
ranked_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.country_id, sd.payment_date
            ORDER BY sd.day_amount DESC
        ) AS country_day_rank
    FROM suspicious_days AS sd
)
SELECT
    customer_name,
    city,
    country,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(r_nc17_share, 4) AS r_nc17_share,
    country_day_rank
FROM ranked_days
ORDER BY
    country,
    payment_date,
    country_day_rank;