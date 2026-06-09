WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        a.e01 AS address_id,
        ci.d02 AS city_name,
        co.c02 AS country_name,
        c.h02 AS home_store_id
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        cg.city_name,
        cg.country_name,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment
    FROM pay p
    JOIN customer_geo cg ON cg.customer_id = p.p02
    JOIN stf s ON s.o01 = p.p03
    GROUP BY
        p.p02, cg.city_name, cg.country_name, date(p.p06)
),
daily_with_personal_avg AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp_prev.day_amount)
            FROM daily_payments dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_day >= date(dp.payment_day, '-30 day')
              AND dp_prev.payment_day < dp.payment_day
        ) AS personal_avg_prev_30d
    FROM daily_payments dp
),
country_days AS (
    SELECT
        country_name,
        payment_day,
        day_amount
    FROM daily_payments
),
country_p95 AS (
    SELECT
        country_name,
        AVG(day_amount) AS p95_day_amount
    FROM (
        SELECT
            cd.*,
            ROW_NUMBER() OVER (PARTITION BY country_name ORDER BY day_amount) AS rn,
            COUNT(*) OVER (PARTITION BY country_name) AS cnt
        FROM country_days cd
    ) t
    WHERE rn > (0.95 * (cnt - 1))
    GROUP BY country_name
),
flagged AS (
    SELECT
        dwp.*,
        (dwp.day_amount - dwp.personal_avg_prev_30d) AS deviation_from_personal_avg,
        cp.p95_day_amount,
        (dwp.day_amount / NULLIF(dwp.personal_avg_prev_30d, 0)) AS personal_ratio_prev_30d
    FROM daily_with_personal_avg dwp
    JOIN country_p95 cp
      ON cp.country_name = dwp.country_name
    WHERE dwp.personal_avg_prev_30d IS NOT NULL
      AND dwp.payment_count >= 3
      AND dwp.staff_count >= 2
      AND dwp.day_amount > 3.0 * dwp.personal_avg_prev_30d
      AND dwp.day_amount > cp.p95_day_amount
),
ranked AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY f.country_name
            ORDER BY (f.day_amount / NULLIF(f.personal_avg_prev_30d, 0)) DESC, f.day_amount DESC, f.customer_id
        ) AS suspicious_rank_in_country
    FROM flagged f
)
SELECT
    customer_id,
    city_name,
    country_name,
    payment_day AS suspicious_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_count,
    store_count,
    first_payment_ts AS first_operation_ts,
    last_payment_ts AS last_operation_ts,
    ROUND(max_payment, 2) AS max_payment,
    suspicious_rank_in_country,
    ROUND(personal_avg_prev_30d, 2) AS personal_avg_prev_30d,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg
FROM ranked
ORDER BY
    country_name,
    suspicious_rank_in_country,
    day_amount DESC,
    customer_id,
    payment_day;