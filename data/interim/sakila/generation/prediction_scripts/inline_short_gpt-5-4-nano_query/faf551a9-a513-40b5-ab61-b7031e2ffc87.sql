WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_base AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COALESCE(s.o07, r.q01) AS store_id,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    GROUP BY
        p.p02,
        DATE(p.p06),
        COALESCE(s.o07, r.q01)
),
daily_by_customer_day AS (
    SELECT
        db.customer_id,
        db.payment_date,
        db.day_amount,
        db.payment_count,
        db.distinct_staff_count,
        FIRST_VALUE(db.store_id) OVER (
            PARTITION BY db.customer_id, db.payment_date
            ORDER BY db.day_amount DESC, db.payment_count DESC
        ) AS store_id
    FROM daily_base AS db
),
daily_scored AS (
    SELECT
        d.customer_id,
        d.payment_date,
        d.store_id,
        d.day_amount,
        d.payment_count,
        d.distinct_staff_count,
        (
            SELECT AVG(d2.day_amount)
            FROM daily_by_customer_day AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= DATE(d.payment_date, '-30 days')
              AND d2.payment_date <  d.payment_date
        ) AS avg_prev_30d
    FROM daily_by_customer_day AS d
),
country_rank AS (
    SELECT
        ds.*,
        RANK() OVER (
            PARTITION BY cg.country_name, ds.payment_date
            ORDER BY ds.day_amount DESC
        ) AS country_day_surge_rank
    FROM daily_scored AS ds
    JOIN customer_geo AS cg ON cg.customer_id = ds.customer_id
),
country_p95 AS (
    SELECT
        country_name,
        payment_date,
        /* p95 by averaging the two middle values around the 95th percentile */
        AVG(day_amount) AS p95_day_amount
    FROM (
        SELECT
            cg.country_name,
            ds.payment_date,
            ds.day_amount,
            ROW_NUMBER() OVER (
                PARTITION BY cg.country_name, ds.payment_date
                ORDER BY ds.day_amount
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY cg.country_name, ds.payment_date
            ) AS cnt
        FROM daily_scored AS ds
        JOIN customer_geo AS cg ON cg.customer_id = ds.customer_id
        WHERE ds.avg_prev_30d IS NOT NULL
    ) t
    WHERE rn IN (
        CAST(0.95 * (cnt - 1) + 1 AS INTEGER),
        CAST(0.95 * (cnt - 1) + 2 AS INTEGER)
    )
    GROUP BY country_name, payment_date
),
final AS (
    SELECT
        ds.customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        ds.payment_date AS surge_date,
        ds.store_id,
        ds.day_amount,
        ds.payment_count,
        ds.avg_prev_30d,
        (ds.day_amount - ds.avg_prev_30d) AS deviation_from_avg,
        cpr.p95_day_amount,
        RANK() OVER (
            PARTITION BY cg.country_name
            ORDER BY ds.day_amount DESC
        ) AS surge_rank_within_country
    FROM daily_scored AS ds
    JOIN customer_geo AS cg ON cg.customer_id = ds.customer_id
    JOIN country_p95 AS cpr
      ON cpr.country_name = cg.country_name
     AND cpr.payment_date = ds.payment_date
    WHERE ds.avg_prev_30d IS NOT NULL
      AND ds.day_amount >= 3.0 * ds.avg_prev_30d
      AND ds.day_amount > cpr.p95_day_amount
)
SELECT
    surge_date AS date_of_surge,
    customer_id,
    first_name,
    last_name,
    country_name AS country,
    city_name AS city,
    store_id AS store_id,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(deviation_from_avg, 2) AS deviation_from_avg,
    surge_rank_within_country AS country_surge_rank
FROM final
ORDER BY
    country,
    surge_rank_within_country,
    date_of_surge,
    customer_id;