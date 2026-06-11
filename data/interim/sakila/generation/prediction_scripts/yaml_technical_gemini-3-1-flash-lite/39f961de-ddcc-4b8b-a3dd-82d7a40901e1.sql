WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT i.n03) AS distinct_store_count,
        SUM(CASE WHEN f.i11 IN ('R', 'NC-17') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS restricted_rating_share
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flm f ON f.i01 = i.n02
    GROUP BY p.p02, date(p.p06)
),
customer_history AS (
    SELECT
        dp.*,
        AVG(dp.daily_sum) OVER (
            PARTITION BY dp.customer_id
            ORDER BY dp.payment_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_30d
    FROM daily_payments dp
),
suspicious_days AS (
    SELECT
        sh.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country,
        cn.c01 AS country_id
    FROM customer_history sh
    JOIN cus c ON c.h01 = sh.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    WHERE sh.avg_prev_30d > 0
      AND sh.daily_sum >= 3 * sh.avg_prev_30d
      AND sh.payment_count >= 3
      AND (sh.distinct_staff_count > 1 OR sh.distinct_store_count > 1)
)
SELECT
    customer_name,
    city,
    country,
    payment_date,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(restricted_rating_share, 4) AS restricted_rating_share,
    RANK() OVER (
        PARTITION BY country_id, payment_date
        ORDER BY daily_sum DESC
    ) AS country_day_rank
FROM suspicious_days
ORDER BY
    country,
    payment_date,
    daily_sum DESC;