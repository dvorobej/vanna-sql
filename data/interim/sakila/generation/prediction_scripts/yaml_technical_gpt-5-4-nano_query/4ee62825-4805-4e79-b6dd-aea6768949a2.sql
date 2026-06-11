WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
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
        date(p.p06) AS payment_day,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(r.q03, -1)) AS store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_single_payment
    FROM pay AS p
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_ranked AS (
    SELECT
        dp.*,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        (
            SELECT AVG(dp_prev.day_amount)
            FROM daily_payments AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_day >= date(dp.payment_day, '-30 day')
              AND dp_prev.payment_day < dp.payment_day
        ) AS personal_avg_prev_30d
    FROM daily_payments AS dp
    JOIN cus AS c ON c.h01 = dp.customer_id
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE c.h07 = 'Y'
),
country_p95 AS (
    SELECT
        country_name,
        payment_day,
        day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY country_name
            ORDER BY day_amount
        ) AS rn,
        COUNT(*) OVER (PARTITION BY country_name) AS cnt
    FROM (
        SELECT
            dp.payment_day,
            cg.country_name,
            dp.day_amount
        FROM daily_ranked AS dp
        JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    ) x
),
country_p95_level AS (
    SELECT
        country_name,
        MAX(day_amount) AS p95_day_amount
    FROM country_p95
    WHERE rn >= CAST(0.95 * cnt AS INTEGER)
    GROUP BY country_name
),
suspicious_cases AS (
    SELECT
        dr.*,
        cpl.p95_day_amount,
        (dr.day_amount - dr.personal_avg_prev_30d) AS deviation_from_personal_avg,
        (dr.day_amount / NULLIF(dr.personal_avg_prev_30d, 0)) AS ratio_vs_personal_avg,
        (dr.day_amount - cpl.p95_day_amount) AS deviation_vs_country_p95
    FROM daily_ranked AS dr
    JOIN country_p95_level AS cpl
        ON cpl.country_name = dr.country_name
    WHERE dr.personal_avg_prev_30d IS NOT NULL
      AND dr.personal_avg_prev_30d > 0
      AND dr.payment_count >= 3
      AND dr.staff_count >= 2
      AND dr.day_amount > 3.0 * dr.personal_avg_prev_30d
      AND dr.day_amount > cpl.p95_day_amount
),
ranked_suspicious AS (
    SELECT
        sc.*,
        RANK() OVER (
            PARTITION BY sc.country_name
            ORDER BY sc.ratio_vs_personal_avg DESC, sc.day_amount DESC, sc.customer_id
        ) AS suspicious_rank_in_country
    FROM suspicious_cases AS sc
)
SELECT
    customer_id,
    customer_name,
    city_name,
    country_name,
    payment_day AS suspicious_date,
    payment_count,
    ROUND(day_amount, 2) AS day_total_amount,
    staff_count,
    store_count,
    first_payment_ts AS first_operation_ts,
    last_payment_ts AS last_operation_ts,
    ROUND(max_single_payment, 2) AS max_payment_in_day,
    suspicious_rank_in_country,
    ROUND(personal_avg_prev_30d, 2) AS avg_daily_amount_prev_30d,
    ROUND(p95_day_amount, 2) AS country_p95_daily_amount
FROM ranked_suspicious
ORDER BY
    country_name,
    suspicious_rank_in_country,
    suspicious_date,
    customer_id;