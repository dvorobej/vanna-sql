WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS country,
        ci.d02 AS city,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
daily_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        COUNT(DISTINCT p.p03) AS staff_distinct_count,
        SUM(CASE WHEN s.o07 <> cg.home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS staff_non_home_payment_share,
        (
            SELECT s2.o01
            FROM pay AS p2
            JOIN stf AS s2 ON s2.o01 = p2.p03
            WHERE p2.p02 = p.p02
              AND date(p2.p06) = date(p.p06)
            GROUP BY s2.o01
            ORDER BY COUNT(*) DESC, s2.o01
            LIMIT 1
        ) AS top_staff_id
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06),
        cg.home_store_id
),
history_stats AS (
    SELECT
        db.customer_id,
        db.payment_date,
        db.payment_count,
        db.day_sum,
        db.staff_distinct_count,
        db.staff_non_home_payment_share,
        db.top_staff_id,
        (
            SELECT AVG(CAST(d.day_sum AS REAL))
            FROM daily_base AS d
            WHERE d.customer_id = db.customer_id
              AND d.payment_date >= date(db.payment_date, '-30 day')
              AND d.payment_date < db.payment_date
        ) AS hist_avg_sum,
        (
            SELECT AVG(CAST(d.payment_count AS REAL))
            FROM daily_base AS d
            WHERE d.customer_id = db.customer_id
              AND d.payment_date >= date(db.payment_date, '-30 day')
              AND d.payment_date < db.payment_date
        ) AS hist_avg_count,
        (
            SELECT
                CASE
                    WHEN COUNT(*) >= 2 THEN
                        sqrt(AVG((CAST(d.day_sum AS REAL) - (
                            SELECT AVG(CAST(d2.day_sum AS REAL))
                            FROM daily_base AS d2
                            WHERE d2.customer_id = db.customer_id
                              AND d2.payment_date >= date(db.payment_date, '-30 day')
                              AND d2.payment_date < db.payment_date
                        )) * (CAST(d.day_sum AS REAL) - (
                            SELECT AVG(CAST(d2.day_sum AS REAL))
                            FROM daily_base AS d2
                            WHERE d2.customer_id = db.customer_id
                              AND d2.payment_date >= date(db.payment_date, '-30 day')
                              AND d2.payment_date < db.payment_date
                        )))) )
                    ELSE NULL
                END
            FROM daily_base AS d
            WHERE d.customer_id = db.customer_id
              AND d.payment_date >= date(db.payment_date, '-30 day')
              AND d.payment_date < db.payment_date
        ) AS hist_std_sum,
        (
            SELECT COUNT(*)
            FROM daily_base AS d
            WHERE d.customer_id = db.customer_id
              AND d.payment_date >= date(db.payment_date, '-30 day')
              AND d.payment_date < db.payment_date
        ) AS hist_days_count,
        (
            SELECT
                CASE
                    WHEN COUNT(*) >= 2 THEN
                        sqrt(AVG((CAST(d.payment_count AS REAL) - (
                            SELECT AVG(CAST(d2.payment_count AS REAL))
                            FROM daily_base AS d2
                            WHERE d2.customer_id = db.customer_id
                              AND d2.payment_date >= date(db.payment_date, '-30 day')
                              AND d2.payment_date < db.payment_date
                        )) * (CAST(d.payment_count AS REAL) - (
                            SELECT AVG(CAST(d2.payment_count AS REAL))
                            FROM daily_base AS d2
                            WHERE d2.customer_id = db.customer_id
                              AND d2.payment_date >= date(db.payment_date, '-30 day')
                              AND d2.payment_date < db.payment_date
                        )))) )
                    ELSE NULL
                END
            FROM daily_base AS d
            WHERE d.customer_id = db.customer_id
              AND d.payment_date >= date(db.payment_date, '-30 day')
              AND d.payment_date < db.payment_date
        ) AS hist_std_count
    FROM daily_base AS db
),
category_main_by_day AS (
    SELECT
        r.q04 AS customer_id,
        date(p.p06) AS payment_date,
        ca.g02 AS main_category,
        ROW_NUMBER() OVER (
            PARTITION BY r.q04, date(p.p06)
            ORDER BY COUNT(*) DESC, ca.g02
        ) AS rn
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat AS ca ON ca.g01 = fc.l02
    WHERE r.q01 IS NOT NULL
    GROUP BY
        r.q04,
        date(p.p06),
        ca.g02
),
risk_scored AS (
    SELECT
        hs.customer_id,
        hs.payment_date,
        hs.payment_count,
        hs.day_sum,
        hs.staff_distinct_count,
        hs.staff_non_home_payment_share,
        hs.top_staff_id,
        hs.hist_avg_sum,
        hs.hist_std_sum,
        hs.hist_days_count,
        hs.hist_avg_count,
        hs.hist_std_count,
        CASE
            WHEN hs.hist_days_count >= 10
             AND hs.hist_std_sum IS NOT NULL
             AND hs.hist_avg_sum IS NOT NULL
             AND hs.day_sum > (hs.hist_avg_sum + 3.0 * hs.hist_std_sum)
            THEN 1 ELSE 0
        END AS flag_sum_z_gt_3,
        CASE
            WHEN hs.hist_days_count >= 10
             AND hs.hist_std_count IS NOT NULL
             AND hs.hist_avg_count IS NOT NULL
             AND hs.payment_count > (hs.hist_avg_count + 3.0 * hs.hist_std_count)
            THEN 1 ELSE 0
        END AS flag_count_z_gt_3,
        CASE
            WHEN hs.hist_days_count >= 10
             AND hs.hist_std_sum IS NOT NULL
             AND hs.hist_avg_sum IS NOT NULL
             AND hs.day_sum > (hs.hist_avg_sum + 3.0 * hs.hist_std_sum)
            THEN 1
            WHEN hs.hist_days_count >= 10
             AND hs.hist_avg_count IS NOT NULL
             AND hs.hist_std_count IS NOT NULL
             AND hs.payment_count > (hs.hist_avg_count + 3.0 * hs.hist_std_count)
            THEN 1
            ELSE 0
        END AS is_suspicious
    FROM history_stats AS hs
    WHERE hs.hist_days_count IS NOT NULL
),
suspicious_ranked AS (
    SELECT
        rs.*,
        RANK() OVER (
            ORDER BY
                CASE WHEN rs.is_suspicious = 1 THEN 1 ELSE 0 END DESC,
                (rs.day_sum - rs.hist_avg_sum) DESC,
                rs.payment_count DESC,
                rs.customer_id,
                rs.payment_date
        ) AS suspicious_rank_global
    FROM risk_scored AS rs
    WHERE rs.is_suspicious = 1
)
SELECT
    sr.customer_id,
    cg.first_name,
    cg.last_name,
    sr.payment_date,
    ROUND(sr.day_sum, 2) AS day_sum,
    sr.payment_count,
    sr.hist_days_count AS history_days_observed,
    ROUND(sr.hist_avg_sum, 2) AS hist_avg_sum,
    ROUND(sr.hist_std_sum, 2) AS hist_std_sum,
    ROUND(sr.hist_avg_count, 2) AS hist_avg_count,
    ROUND(sr.hist_std_count, 2) AS hist_std_count,
    sr.flag_sum_z_gt_3 AS flag_sum_outlier,
    sr.flag_count_z_gt_3 AS flag_count_outlier,
    sr.staff_non_home_payment_share,
    cg.country,
    cg.city,
    sr.top_staff_id AS top_staff_id,
    st.o02 || ' ' || st.o03 AS top_staff_name,
    mc.main_category AS main_category,
    sr.suspicious_rank_global AS suspicious_rank
FROM suspicious_ranked AS sr
JOIN customer_geo AS cg ON cg.customer_id = sr.customer_id
LEFT JOIN stf AS st ON st.o01 = sr.top_staff_id
LEFT JOIN category_main_by_day AS mc
  ON mc.customer_id = sr.customer_id
 AND mc.payment_date = sr.payment_date
 AND mc.rn = 1
ORDER BY
    sr.day_sum DESC,
    sr.payment_count DESC,
    sr.payment_date,
    sr.customer_id;