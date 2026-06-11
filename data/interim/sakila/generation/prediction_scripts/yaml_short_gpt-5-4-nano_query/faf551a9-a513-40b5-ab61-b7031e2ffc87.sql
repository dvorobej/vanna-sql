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
daily_by_customer AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    GROUP BY
        p.p02,
        date(p.p06),
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name
),
daily_enriched AS (
    SELECT
        dbc.*,
        (
            SELECT AVG(d2.day_amount)
            FROM daily_by_customer AS d2
            WHERE d2.customer_id = dbc.customer_id
              AND d2.payment_day >= date(dbc.payment_day, '-30 day')
              AND d2.payment_day < dbc.payment_day
        ) AS avg_prev_30d,
        (
            SELECT d3.day_amount
            FROM daily_by_customer AS d3
            WHERE d3.country_name = dbc.country_name
              AND d3.payment_day = dbc.payment_day
            ORDER BY d3.day_amount DESC
            LIMIT 1 OFFSET CAST(0.05 * (
                SELECT COUNT(*)
                FROM daily_by_customer AS d4
                WHERE d4.country_name = dbc.country_name
                  AND d4.payment_day = dbc.payment_day
            ) AS INTEGER)
        ) AS p95_threshold_approx
    FROM daily_by_customer AS dbc
),
flagged_days AS (
    SELECT
        de.*,
        (de.day_amount - de.avg_prev_30d) AS deviation_from_personal_avg
    FROM daily_enriched AS de
    WHERE de.avg_prev_30d IS NOT NULL
      AND de.avg_prev_30d > 0
      AND de.day_amount >= 3.0 * de.avg_prev_30d
      AND de.day_amount > de.p95_threshold_approx
),
staff_store_breakdown AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        group_concat(DISTINCT (st.o02 || ' ' || st.o03)) AS staff_list,
        COUNT(DISTINCT p.p03) AS distinct_staff_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
)
SELECT
    fd.payment_day AS splash_date,
    fd.first_name,
    fd.last_name,
    fd.country_name AS country,
    fd.city_name AS city,
    ssb.staff_list AS store_and_staff,   -- по контексту: магазин/сотрудник;