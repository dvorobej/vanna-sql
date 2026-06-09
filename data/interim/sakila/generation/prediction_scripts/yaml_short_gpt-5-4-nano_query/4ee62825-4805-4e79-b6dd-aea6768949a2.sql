WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ci.d02 AS city_name,
        cnt.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
daily_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_personal_avg AS (
    SELECT
        db.*,
        (
            SELECT AVG(db_prev.day_amount)
            FROM daily_base AS db_prev
            WHERE db_prev.customer_id = db.customer_id
              AND db_prev.payment_date >= date(db.payment_date, '-30 day')
              AND db_prev.payment_date < db.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_base AS db
),
country_daily_ranked AS (
    SELECT
        db.payment_date,
        cg.country_name,
        db.day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY cg.country_name, db.payment_date
            ORDER BY db.day_amount
        ) AS rn_asc,
        COUNT(*) OVER (
            PARTITION BY cg.country_name, db.payment_date
        ) AS cnt_days
    FROM daily_with_personal_avg AS db
    JOIN customer_geo AS cg ON cg.customer_id = db.customer_id
),
country_daily_p95 AS (
    SELECT
        country_name,
        payment_date,
        MAX(CASE WHEN rn_asc >= CAST((cnt_days * 0.95) AS INTEGER) THEN day_amount END) AS p95_day_amount
    FROM country_daily_ranked
    GROUP BY country_name, payment_date
),
scored AS (
    SELECT
        db.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        db.payment_date,
        db.payment_count,
        db.day_amount,
        db.distinct_staff_count,
        db.distinct_store_count,
        db.first_payment_ts,
        db.last_payment_ts,
        db.max_payment_amount,
        db.personal_avg_prev_30d,
        cdp.p95_day_amount,
        (db.day_amount - db.personal_avg_prev_30d) AS deviation_from_personal_avg,
        (db.day_amount / NULLIF(db.personal_avg_prev_30d, 0)) AS ratio_vs_personal_avg
    FROM daily_with_personal_avg AS db
    JOIN customer_geo AS cg ON cg.customer_id = db.customer_id
    JOIN country_daily_p95 AS cdp
      ON cdp.country_name = cg.country_name
     AND cdp.payment_date = db.payment_date
    WHERE db.personal_avg_prev_30d IS NOT NULL
)
SELECT
    s.customer_id,
    s.customer_name,
    s.city_name,
    s.country_name,
    s.payment_date,
    s.payment_count,
    ROUND(s.day_amount, 2) AS day_amount,
    s.distinct_staff_count AS staff_count_distinct,
    s.distinct_store_count AS stores_count_distinct,
    s.first_payment_ts AS first_payment_time,
    s.last_payment_ts AS last_payment_time,
    ROUND(s.max_payment_amount, 2) AS max_payment_amount,
    RANK() OVER (
        PARTITION BY s.country_name
        ORDER BY s.day_amount - s.personal_avg_prev_30d DESC
    ) AS suspicion_rank_in_country
FROM scored AS s
WHERE s.payment_count >= 3
  AND s.distinct_staff_count >= 2
  AND s.day_amount > 3.0 * s.personal_avg_prev_30d
  AND s.day_amount > s.p95_day_amount
ORDER BY
    s.country_name,
    suspicion_rank_in_country,
    s.payment_date,
    s.customer_id;