SELECT AVG(db2.day_sum)
            FROM daily_base AS db2
            WHERE db2.customer_id = db.customer_id
              AND db2.payment_day >= date(db.payment_day, '-30 days')
              AND db2.payment_day < db.payment_day
        ) AS avg_prev_30d,
        (
            SELECT
                CASE
                    WHEN COUNT(*) > 0 THEN
                        sqrt(
                            AVG(db2.day_sum * db2.day_sum) - AVG(db2.day_sum) * AVG(db2.day_sum)
                        )
                ELSE NULL
                END
            FROM daily_base AS db2
            WHERE db2.customer_id = db.customer_id
              AND db2.payment_day >= date(db.payment_day, '-30 days')
              AND db2.payment_day < db.payment_day
        ) AS std_prev_30d,
        (
            SELECT AVG(db2.payment_count)
            FROM daily_base AS db2
            WHERE db2.customer_id = db.customer_id
              AND db2.payment_day >= date(db.payment_day, '-30 days')
              AND db2.payment_day < db.payment_day
        ) AS avg_prev_30d_payment_count,
        (
            SELECT COUNT(*) 
            FROM daily_base AS db2
            WHERE db2.customer_id = db.customer_id
              AND db2.payment_day >= date(db.payment_day, '-30 days')
              AND db2.payment_day < db.payment_day
        ) AS prev_days_cnt
    FROM daily_base AS db
),
flagged_days AS (
    SELECT
        rs.*,
        CASE
            WHEN rs.prev_days_cnt >= 10
             AND rs.std_prev_30d IS NOT NULL
             AND rs.day_sum > rs.avg_prev_30d + 3.0 * rs.std_prev_30d
            THEN 1 ELSE 0
        END AS is_sum_anomaly,
        CASE
            WHEN rs.prev_days_cnt >= 10
             AND rs.avg_prev_30d_payment_count IS NOT NULL
             AND rs.payment_count >= 2.0 * rs.avg_prev_30d_payment_count
            THEN 1 ELSE 0
        END AS is_count_spike,
        CASE
            WHEN rs.prev_days_cnt >= 10
             AND rs.std_prev_30d IS NOT NULL
             AND rs.avg_prev_30d IS NOT NULL
            THEN (rs.day_sum - rs.avg_prev_30d) / NULLIF(rs.std_prev_30d, 0)
        END AS z_score_sum
    FROM rolling_stats AS rs
    WHERE rs.prev_days_cnt >= 10
),
risk_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        p.p05 AS payment_amount,
        date(p.p06) AS payment_day,
        ren.q03 AS inventory_id,
        inv.n02 AS film_id,
        inv.n03 AS store_id_issuing,
        rstock.film_category_id,
        flc.l02 AS category_id,
        flc_main.cat_main
    FROM pay AS p
    LEFT JOIN ren
        ON ren.q01 = p.p04
    LEFT JOIN inv
        ON inv.n01 = ren.q03
    LEFT JOIN (
        SELECT NULL AS film_category_id
    ) AS rstock
        ON 1=0
    LEFT JOIN flc
        ON flc.l01 = inv.n02
    LEFT JOIN (
        SELECT
            l01 AS film_id,
            MAX(l02) AS cat_main
        FROM flc
        GROUP BY l01
    ) AS flc_main
        ON flc_main.film_id = inv.n02
    WHERE p.p06 IS NOT NULL
),
day_staff_country_ratio AS (
    SELECT
        c.h01 AS customer_id,
        date(p.p06) AS payment_day,
        SUM(CASE WHEN p.p03 <> NULL AND s.o07 <> c.h02 THEN CAST(p.p05 AS REAL) ELSE 0 END) AS foreign_store_staff_sum,
        SUM(CAST(p.p05 AS REAL)) AS total_day_sum_for_ratio,
        CASE
            WHEN SUM(CAST(p.p05 AS REAL)) > 0
            THEN 1.0 * SUM(CASE WHEN s.o07 <> c.h02 THEN CAST(p.p05 AS REAL) ELSE 0 END) / SUM(CAST(p.p05 AS REAL))
        END AS foreign_store_staff_share
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY c.h01, date(p.p06)
),
day_top_staff AS (
    SELECT
        x.customer_id,
        x.payment_day,
        x.staff_id,
        x.staff_sum,
        ROW_NUMBER() OVER (
            PARTITION BY x.customer_id, x.payment_day
            ORDER BY x.staff_sum DESC, x.staff_id
        ) AS rn
    FROM (
        SELECT
            p.p02 AS customer_id,
            date(p.p06) AS payment_day,
            p.p03 AS staff_id,
            SUM(CAST(p.p05 AS REAL)) AS staff_sum
        FROM pay AS p
        GROUP BY p.p02, date(p.p06), p.p03
    ) AS x
),
day_top_category AS (
    SELECT
        y.customer_id,
        y.payment_day,
        y.category_id,
        y.category_sum,
        ROW_NUMBER() OVER (
            PARTITION BY y.customer_id, y.payment_day
            ORDER BY y.category_sum DESC, y.category_id
        ) AS rn
    FROM (
        SELECT
            p.p02 AS customer_id,
            date(p.p06) AS payment_day,
            flc.l02 AS category_id,
            SUM(CAST(p.p05 AS REAL)) AS category_sum
        FROM pay AS p
        JOIN ren
            ON ren.q01 = p.p04
        JOIN inv
            ON inv.n01 = ren.q03
        JOIN flc
            ON flc.l01 = inv.n02
        GROUP BY p.p02, date(p.p06), flc.l02
    ) AS y
)
SELECT
    fd.customer_id AS h01_customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    cnt.c02 AS customer_country,
    cty.d02 AS customer_city,
    fd.payment_day AS suspicious_date,
    fd.payment_count,
    fd.day_sum,
    fd.avg_prev_30d AS personal_avg_prev_30d,
    fd.std_prev_30d AS personal_std_prev_30d,
    fd.z_score_sum,
    CASE
        WHEN fd.is_sum_anomaly = 1 AND fd.is_count_spike = 1 THEN 1
        WHEN fd.is_sum_anomaly = 1 THEN 0.8
        WHEN fd.is_count_spike = 1 THEN 0.6
        ELSE 0
    END AS risk_level_score,
    MAX(CASE WHEN ds.rn = 1 THEN ds.staff_id END) AS top_staff_id,
    MAX(CASE WHEN ds.rn = 1 THEN st.o02 END) AS top_staff_first_name,
    MAX(CASE WHEN ds.rn = 1 THEN st.o03 END) AS top_staff_last_name,
    MAX(CASE WHEN dc.rn = 1 THEN dc.category_id END) AS top_category_id,
    MAX(cat.g02) AS top_category_name,
    dscr.foreign_store_staff_share AS foreign_store_staff_share,
    RANK() OVER (
        PARTITION BY fd.customer_id
        ORDER BY
            (CASE
                WHEN fd.is_sum_anomaly = 1 AND fd.is_count_spike = 1 THEN 1
                WHEN fd.is_sum_anomaly = 1 THEN 0.8
                WHEN fd.is_count_spike = 1 THEN 0.6
                ELSE 0
             END) DESC,
            fd.day_sum DESC
    ) AS suspicion_rank_within_customer
FROM flagged_days AS fd
JOIN cus AS c
    ON c.h01 = fd.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty AS cty
    ON cty.d01 = a.e05
JOIN cnt
    ON cnt.c01 = cty.d03
LEFT JOIN day_staff_country_ratio AS dscr
    ON dscr.customer_id = fd.customer_id
   AND dscr.payment_day = fd.payment_day
LEFT JOIN day_top_staff AS ds
    ON ds.customer_id = fd.customer_id
   AND ds.payment_day = fd.payment_day
   AND ds.rn = 1
LEFT JOIN stf AS st
    ON st.o01 = ds.staff_id
LEFT JOIN day_top_category AS dc
    ON dc.customer_id = fd.customer_id
   AND dc.payment_day = fd.payment_day
   AND dc.rn = 1
LEFT JOIN cat
    ON cat.g01 = dc.category_id
WHERE fd.is_sum_anomaly = 1 OR fd.is_count_spike = 1
GROUP BY
    fd.customer_id, c.h03, c.h04, cnt.c02, cty.d02,
    fd.payment_day, fd.payment_count, fd.day_sum,
    fd.avg_prev_30d, fd.std_prev_30d, fd.z_score_sum,
    fd.is_sum_anomaly, fd.is_count_spike,
    dscr.foreign_store_staff_share
ORDER BY
    foreign_store_staff_share DESC,
    fd.day_sum DESC,
    fd.customer_id,
    fd.payment_day;