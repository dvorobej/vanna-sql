WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        SUM(CASE WHEN f.i11 IN ('R', 'NC-17') THEN 1 ELSE 0 END) AS restricted_rating_count,
        COUNT(*) AS total_films_count
    FROM pay AS p
    JOIN ren AS r ON p.p04 = r.q01
    JOIN inv AS i ON r.q03 = i.n01
    JOIN flm AS f ON i.n02 = f.i01
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        dp.*,
        (
            SELECT AVG(h.day_amount)
            FROM daily_payments AS h
            WHERE h.customer_id = dp.customer_id
              AND h.payment_date >= date(dp.payment_date, '-30 days')
              AND h.payment_date < dp.payment_date
        ) AS avg_prev_30_days
    FROM daily_payments AS dp
),
suspicious_activity AS (
    SELECT
        hs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id
    FROM history_stats AS hs
    JOIN cus AS c ON hs.customer_id = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    WHERE hs.avg_prev_30_days IS NOT NULL
      AND hs.day_amount > 3 * hs.avg_prev_30_days
      AND (hs.staff_count > 1 OR hs.store_count > 1)
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(CAST(restricted_rating_count AS REAL) / total_films_count, 4) AS restricted_rating_share,
    RANK() OVER (PARTITION BY country_id, payment_date ORDER BY day_amount DESC) AS country_day_rank
FROM suspicious_activity
ORDER BY country, payment_date, country_day_rank;