WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        city.d02 AS city_name,
        country.c01 AS country_id,
        country.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS country
        ON country.c01 = city.d03
),
payment_detail AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        st.o07 AS store_id,
        p.p04 AS rental_id
    FROM pay AS p
    JOIN stf AS st
        ON st.o01 = p.p03
),
daily_customer AS (
    SELECT
        customer_id,
        payment_day,
        SUM(amount) AS daily_amount,
        COUNT(*) AS daily_payment_count,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT store_id) AS store_count,
        COUNT(DISTINCT rental_id) AS rental_count
    FROM payment_detail
    GROUP BY
        customer_id,
        payment_day
),
daily_baseline AS (
    SELECT
        dc.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= date(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ) AS avg_prev_30d_amount,
        (
            SELECT AVG(prev.daily_payment_count)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= date(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ) AS avg_prev_30d_count,
        (
            SELECT COUNT(*)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= date(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ) AS history_days_30d
    FROM daily_customer AS dc
),
country_ranked AS (
    SELECT
        db.*,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        RANK() OVER (
            PARTITION BY cg.country_id, db.payment_day
            ORDER BY db.daily_amount DESC, db.daily_payment_count DESC, db.customer_id
        ) AS country_day_amount_rank,
        COUNT(*) OVER (
            PARTITION BY cg.country_id, db.payment_day
        ) AS country_day_customer_count
    FROM daily_baseline AS db
    JOIN customer_geo AS cg
        ON cg.customer_id = db.customer_id
),
country_p95 AS (
    SELECT
        country_id,
        payment_day,
        MIN(daily_amount) AS p95_daily_amount
    FROM (
        SELECT
            country_id,
            payment_day,
            daily_amount,
            CUME_DIST() OVER (
                PARTITION BY country_id, payment_day
                ORDER BY daily_amount
            ) AS cd
        FROM country_ranked
    )
    WHERE cd >= 0.95
    GROUP BY country_id, payment_day
)
SELECT
    cr.customer_id,
    cr.customer_name,
    cr.city_name,
    cr.country_name,
    cr.payment_day,
    cr.daily_payment_count,
    ROUND(cr.daily_amount, 2) AS daily_amount,
    ROUND(cr.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    ROUND(cr.avg_prev_30d_count, 2) AS avg_prev_30d_count,
    cr.staff_count,
    cr.store_count,
    cr.rental_count,
    cr.country_day_amount_rank,
    ROUND(cp.p95_daily_amount, 2) AS country_p95_daily_amount,
    CASE
        WHEN cr.staff_count > 1 OR cr.store_count > 1 THEN 1
        ELSE 0
    END AS multi_staff_or_store_flag
FROM country_ranked AS cr
JOIN country_p95 AS cp
    ON cp.country_id = cr.country_id
   AND cp.payment_day = cr.payment_day
WHERE cr.history_days_30d >= 5
  AND cr.avg_prev_30d_amount IS NOT NULL
  AND cr.avg_prev_30d_count IS NOT NULL
  AND cr.daily_amount >= 3.0 * cr.avg_prev_30d_amount
  AND cr.daily_payment_count >= 3.0 * cr.avg_prev_30d_count
  AND cr.daily_amount >= cp.p95_daily_amount
ORDER BY
    cr.payment_day,
    cr.country_name,
    cr.country_day_amount_rank,
    cr.daily_amount DESC,
    cr.customer_id;