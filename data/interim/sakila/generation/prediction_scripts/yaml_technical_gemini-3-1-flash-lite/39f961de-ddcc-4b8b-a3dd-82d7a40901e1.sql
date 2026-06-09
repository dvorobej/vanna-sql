WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(*) AS payment_count,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT i.n03) AS distinct_store_count,
        SUM(CASE WHEN f.i11 IN ('R', 'NC-17') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS restricted_film_share
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flm AS f ON f.i01 = i.n02
    GROUP BY p.p02, date(p.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(h.daily_sum)
            FROM daily_payments AS h
            WHERE h.customer_id = dp.customer_id
              AND h.payment_date >= date(dp.payment_date, '-30 days')
              AND h.payment_date < dp.payment_date
        ) AS avg_prev_30d
    FROM daily_payments AS dp
    WHERE dp.payment_count >= 3
      AND (dp.distinct_staff_count > 1 OR dp.distinct_store_count > 1)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country,
        cn.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
),
suspicious_days AS (
    SELECT
        dwh.*,
        cg.customer_name,
        cg.city,
        cg.country,
        cg.country_id
    FROM daily_with_history AS dwh
    JOIN customer_geo AS cg ON cg.customer_id = dwh.customer_id
    WHERE dwh.avg_prev_30d > 0
      AND dwh.daily_sum >= 3 * dwh.avg_prev_30d
),
ranked_days AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY country_id, payment_date
            ORDER BY daily_sum DESC
        ) AS country_day_rank
    FROM suspicious_days
)
SELECT
    customer_name,
    city,
    country,
    payment_date,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(restricted_film_share, 4) AS restricted_film_share,
    country_day_rank
FROM ranked_days
ORDER BY
    country,
    daily_sum DESC,
    payment_date;