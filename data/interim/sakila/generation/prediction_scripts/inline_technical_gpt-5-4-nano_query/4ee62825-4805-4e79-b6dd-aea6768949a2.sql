WITH daily_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        ci.d02 AS city_name,
        co.c02 AS country_name,
        co.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
daily_joined AS (
    SELECT
        dss.*,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        (
            SELECT AVG(d2.day_amount)
            FROM daily_staff_store AS d2
            WHERE d2.customer_id = dss.customer_id
              AND d2.payment_date >= DATE(dss.payment_date, '-30 days')
              AND d2.payment_date < dss.payment_date
        ) AS personal_avg_30d,
        (
            SELECT AVG(d2.day_amount)
            FROM daily_staff_store AS d2
            WHERE d2.customer_id = dss.customer_id
              AND d2.payment_date >= DATE(dss.payment_date, '-30 days')
              AND d2.payment_date < dss.payment_date
        ) AS personal_avg_check -- duplicate for readability
    FROM daily_staff_store AS dss
    JOIN customer_geo AS cg
        ON cg.customer_id = dss.customer_id
),
country_p95 AS (
    SELECT
        country_id,
        payment_date,
        day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, payment_date
            ORDER BY day_amount
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY country_id, payment_date
        ) AS cnt
    FROM (
        SELECT
            dj.country_id,
            dj.payment_date,
            dj.day_amount
        FROM daily_joined AS dj
        WHERE dj.day_amount IS NOT NULL
    )
),
country_p95_value AS (
    SELECT
        country_id,
        payment_date,
        MAX(CASE
            WHEN rn >= CAST((95 * cnt + 99) / 100 AS INTEGER) THEN day_amount
            ELSE NULL
        END) AS p95_day_amount
    FROM country_p95
    GROUP BY country_id, payment_date
),
scored AS (
    SELECT
        dj.customer_id,
        dj.city_name,
        dj.country_name,
        dj.country_id,
        dj.payment_date,
        dj.payment_count,
        dj.day_amount,
        dj.first_payment_ts,
        dj.last_payment_ts,
        dj.max_payment,
        dj.distinct_staff_count,
        dj.distinct_store_count,
        dj.personal_avg_30d,
        cp.p95_day_amount,
        (dj.day_amount - dj.personal_avg_30d) AS deviation_from_personal_avg,
        CASE
            WHEN dj.personal_avg_30d > 0 THEN dj.day_amount / dj.personal_avg_30d
            ELSE NULL
        END AS personal_ratio,
        CASE
            WHEN cp.p95_day_amount > 0 THEN dj.day_amount / cp.p95_day_amount
            ELSE NULL
        END AS country_ratio
    FROM daily_joined AS dj
    JOIN country_p95_value AS cp
      ON cp.country_id = dj.country_id
     AND cp.payment_date = dj.payment_date
    WHERE dj.personal_avg_30d IS NOT NULL
      AND cp.p95_day_amount IS NOT NULL
      AND dj.personal_avg_30d > 0
      AND cp.p95_day_amount > 0
),
filtered AS (
    SELECT
        s.*,
        RANK() OVER (
            PARTITION BY s.country_id, s.payment_date
            ORDER BY (s.day_amount / s.personal_avg_30d) DESC, s.day_amount DESC, s.customer_id
        ) AS suspicion_rank_in_country
    FROM scored AS s
    WHERE s.payment_count >= 3
      AND s.distinct_staff_count >= 2
      AND s.day_amount > 3.0 * s.personal_avg_30d
      AND s.day_amount > s.p95_day_amount
      AND s.distinct_store_count >= 1
)
SELECT
    customer_id,
    city_name,
    country_name,
    payment_date AS suspicious_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    distinct_staff_count AS staff_count,
    distinct_store_count AS store_count,
    first_payment_ts,
    last_payment_ts,
    ROUND(max_payment, 2) AS max_payment,
    suspicion_rank_in_country AS suspicion_rank_by_exceedance
FROM filtered
ORDER BY
    country_name,
    suspicious_date,
    suspicion_rank_in_country,
    day_amount DESC,
    customer_id;