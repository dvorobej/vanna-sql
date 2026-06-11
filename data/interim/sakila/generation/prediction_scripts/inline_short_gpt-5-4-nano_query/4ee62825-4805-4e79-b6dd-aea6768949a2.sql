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
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_baseline AS (
    SELECT
        dp.*,
        COALESCE((
            SELECT AVG(CAST(prev.day_amount AS REAL))
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 day')
              AND prev.payment_date < dp.payment_date
        ), 0.0) AS avg_prev_30d
    FROM daily_payments AS dp
),
country_days AS (
    SELECT
        dp.payment_date,
        cg.country_name,
        dp.day_amount
    FROM daily_with_baseline AS dp
    JOIN customer_geo AS cg
      ON cg.customer_id = dp.customer_id
),
country_thresholds AS (
    -- 95-й перцентиль по дневным суммам внутри страны (берём как значение, при котором доля дней < порога не превышает 5%)
    SELECT
        country_name,
        MAX(day_amount) AS p95_day_amount
    FROM (
        SELECT
            country_name,
            day_amount,
            ROW_NUMBER() OVER (
                PARTITION BY country_name
                ORDER BY day_amount
            ) AS rn,
            COUNT(*) OVER (PARTITION BY country_name) AS cnt
        FROM country_days
    )
    WHERE rn >= CAST(0.95 * cnt AS INTEGER)
    GROUP BY country_name
),
scored AS (
    SELECT
        d.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        d.payment_date,
        d.payment_count,
        d.day_amount,
        d.staff_count,
        d.store_count,
        d.first_payment_ts,
        d.last_payment_ts,
        d.max_payment_amount,
        d.avg_prev_30d,
        (d.day_amount / NULLIF(d.avg_prev_30d, 0)) AS amount_vs_personal_avg_ratio
    FROM daily_with_baseline AS d
    JOIN customer_geo AS cg
      ON cg.customer_id = d.customer_id
    JOIN country_thresholds AS ct
      ON ct.country_name = cg.country_name
    WHERE d.avg_prev_30d > 0
      AND d.payment_count >= 3
      AND d.staff_count >= 2
      AND d.day_amount > 3.0 * d.avg_prev_30d
      AND d.day_amount > ct.p95_day_amount
),
ranked AS (
    SELECT
        s.*,
        RANK() OVER (
            PARTITION BY s.country_name
            ORDER BY (s.day_amount / NULLIF(s.avg_prev_30d, 0)) DESC,
                     s.day_amount DESC,
                     s.customer_id
        ) AS suspicious_rank_in_country
    FROM scored AS s
)
SELECT
    customer_id,
    customer_name,
    city_name,
    country_name,
    payment_date AS suspicious_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_count AS used_staff_count,
    store_count AS used_store_count,
    first_payment_ts,
    last_payment_ts,
    ROUND(max_payment_amount, 2) AS max_payment_amount,
    suspicious_rank_in_country
FROM ranked
ORDER BY
    country_name,
    suspicious_rank_in_country,
    suspicious_date,
    customer_id;