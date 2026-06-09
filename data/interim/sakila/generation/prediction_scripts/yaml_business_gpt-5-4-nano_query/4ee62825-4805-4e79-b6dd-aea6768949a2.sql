WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = ci.d03
    WHERE c.h07 = 'Y'
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT COALESCE(sto.j01, c.h02)) AS distinct_store_count,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    LEFT JOIN sto
        ON sto.j01 = c.h02
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_avgs AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp_prev.day_amount)
            FROM daily_payments AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_date >= date(dp.payment_date, '-30 day')
              AND dp_prev.payment_date < dp.payment_date
        ) AS personal_avg_daily_prev_30d
    FROM daily_payments AS dp
),
country_day_values AS (
    SELECT
        cg.country_name,
        dp.payment_date,
        dp.day_amount
    FROM daily_with_avgs AS dp
    JOIN customer_geo AS cg
        ON cg.customer_id = dp.customer_id
),
country_p95 AS (
    SELECT country_name, payment_date, day_amount
    FROM (
        SELECT
            country_name,
            day_amount,
            ROW_NUMBER() OVER (
                PARTITION BY country_name
                ORDER BY day_amount
            ) AS rn,
            COUNT(*) OVER (PARTITION BY country_name) AS cnt
        FROM country_day_values
    )
    WHERE rn >= CAST((95.0 * cnt + 99) / 100 AS INTEGER)
),
suspicious_cases AS (
    SELECT
        dp.customer_id,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        dp.payment_date,
        dp.payment_count,
        dp.day_amount,
        dp.distinct_staff_count,
        dp.distinct_store_count,
        dp.first_payment_ts,
        dp.last_payment_ts,
        dp.max_payment,
        dp.day_amount / NULLIF(dp.personal_avg_daily_prev_30d, 0) AS exceed_ratio_vs_personal_avg,
        (dp.day_amount - dp.personal_avg_daily_prev_30d) AS deviation_from_personal_avg,
        cp.p95_value AS country_p95_daily_sum,
        dp.day_amount - cp.p95_value AS deviation_from_country_p95
    FROM daily_with_avgs AS dp
    JOIN customer_geo AS cg
        ON cg.customer_id = dp.customer_id
    JOIN (
        SELECT country_name, MAX(day_amount) AS p95_value
        FROM country_p95
        GROUP BY country_name
    ) AS cp
        ON cp.country_name = cg.country_name
    WHERE dp.personal_avg_daily_prev_30d IS NOT NULL
      AND dp.payment_count >= 3
      AND dp.distinct_staff_count >= 2
      AND dp.day_amount >= 3.0 * dp.personal_avg_daily_prev_30d
      AND dp.day_amount > cp.p95_value
),
ranked AS (
    SELECT
        sc.*,
        RANK() OVER (
            PARTITION BY sc.country_name
            ORDER BY (sc.day_amount - sc.personal_avg_daily_prev_30d) DESC, sc.day_amount DESC, sc.payment_date, sc.customer_id
        ) AS suspicion_rank_in_country
    FROM (
        SELECT
            sc.*,
            sc.exceed_ratio_vs_personal_avg
        FROM suspicious_cases sc
    ) sc
)
SELECT
    customer_id,
    customer_name,
    city_name,
    country_name,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    distinct_staff_count,
    distinct_store_count,
    first_payment_ts,
    last_payment_ts,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    suspicion_rank_in_country
FROM ranked
ORDER BY
    country_name,
    suspicion_rank_in_country,
    day_amount DESC,
    payment_date,
    customer_id;