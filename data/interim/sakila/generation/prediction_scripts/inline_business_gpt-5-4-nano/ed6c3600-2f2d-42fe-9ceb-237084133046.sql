WITH daily_by_customer AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        COUNT(*) AS day_payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_with_home_store AS (
    SELECT
        db.customer_id,
        db.payment_day,
        db.day_sum,
        db.day_payment_count,
        db.distinct_staff_count,
        cg.country_name,
        cg.city_name,
        cg.home_store_id,
        SUM(CASE WHEN st.o07 <> cg.home_store_id THEN 1 ELSE 0 END) AS non_home_staff_payment_count,
        SUM(CASE WHEN st.o07 <> cg.home_store_id THEN CAST(p.p05 AS REAL) ELSE 0 END) AS non_home_staff_payment_sum
    FROM daily_by_customer AS db
    JOIN pay AS p
      ON p.p02 = db.customer_id
     AND date(p.p06) = db.payment_day
    JOIN customer_geo AS cg
      ON cg.customer_id = p.p02
    JOIN stf AS st
      ON st.o01 = p.p03
    GROUP BY
        db.customer_id,
        db.payment_day,
        db.day_sum,
        db.day_payment_count,
        db.distinct_staff_count,
        cg.country_name,
        cg.city_name,
        cg.home_store_id
),
risk_stats AS (
    SELECT
        dwhs.*,
        /* mean/std for day_sum over previous 30 days */
        (
            SELECT AVG(CAST(dwhs2.day_sum AS REAL))
            FROM daily_with_home_store AS dwhs2
            WHERE dwhs2.customer_id = dwhs.customer_id
              AND dwhs2.payment_day >= date(dwhs.payment_day, '-30 days')
              AND dwhs2.payment_day < dwhs.payment_day
        ) AS mean_sum_prev_30d,
        (
            SELECT AVG(CAST(dwhs2.day_sum AS REAL) * CAST(dwhs2.day_sum AS REAL))
            FROM daily_with_home_store AS dwhs2
            WHERE dwhs2.customer_id = dwhs.customer_id
              AND dwhs2.payment_day >= date(dwhs.payment_day, '-30 days')
              AND dwhs2.payment_day < dwhs.payment_day
        ) AS mean_sq_sum_prev_30d,
        (
            SELECT COUNT(*)
            FROM daily_with_home_store AS dwhs2
            WHERE dwhs2.customer_id = dwhs.customer_id
              AND dwhs2.payment_day >= date(dwhs.payment_day, '-30 days')
              AND dwhs2.payment_day < dwhs.payment_day
        ) AS obs_days_prev_30d
    FROM daily_with_home_store AS dwhs
),
risk_scored AS (
    SELECT
        rs.*,
        /* std = sqrt(E[X^2] - (E[X])^2) */
        CASE
            WHEN rs.mean_sum_prev_30d IS NULL OR rs.mean_sq_sum_prev_30d IS NULL THEN NULL
            ELSE MAX(0.0, rs.mean_sq_sum_prev_30d - (rs.mean_sum_prev_30d * rs.mean_sum_prev_30d))
        END AS var_sum_prev_30d,
        CASE
            WHEN rs.mean_sum_prev_30d IS NULL OR rs.mean_sq_sum_prev_30d IS NULL THEN NULL
            ELSE sqrt(MAX(0.0, rs.mean_sq_sum_prev_30d - (rs.mean_sum_prev_30d * rs.mean_sum_prev_30d)))
        END AS std_sum_prev_30d
    FROM risk_stats AS rs
),
daily_suspicious AS (
    SELECT
        r.*,
        CASE
            WHEN r.obs_days_prev_30d >= 15
             AND r.std_sum_prev_30d IS NOT NULL
             AND r.std_sum_prev_30d > 0
             AND r.day_sum > r.mean_sum_prev_30d + 3 * r.std_sum_prev_30d
            THEN 1 ELSE 0
        END AS flag_sum_gt_3std,
        /* identify sharp growth in count: compare to mean of previous 30d for count */
        (
            SELECT AVG(CAST(dwhs2.day_payment_count AS REAL))
            FROM daily_with_home_store AS dwhs2
            WHERE dwhs2.customer_id = r.customer_id
              AND dwhs2.payment_day >= date(r.payment_day, '-30 days')
              AND dwhs2.payment_day < r.payment_day
        ) AS mean_count_prev_30d
    FROM risk_scored AS r
),
daily_suspicious_final AS (
    SELECT
        ds.*,
        CASE
            WHEN ds.mean_count_prev_30d IS NOT NULL
             AND ds.mean_count_prev_30d > 0
             AND ds.day_payment_count >= ds.mean_count_prev_30d * 2.5
            THEN 1 ELSE 0
        END AS flag_count_growth,
        (CAST(ds.non_home_staff_payment_sum AS REAL) / NULLIF(CAST(ds.day_sum AS REAL), 0.0)) AS non_home_payment_sum_share
    FROM daily_suspicious AS ds
),
daily_category AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        (
            SELECT ca.g02
            FROM pay p2
            JOIN ren r2 ON r2.q01 = p2.p04
            JOIN inv i2 ON i2.n01 = r2.q03
            JOIN flc fc2 ON fc2.l01 = i2.n02
            JOIN cat ca ON ca.g01 = fc2.l02
            WHERE p2.p02 = p.p02
              AND date(p2.p06) = date(p.p06)
            GROUP BY ca.g02
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) AS main_category
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
main_staff AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        st.o01 AS staff_id,
        st.o02 AS staff_first_name,
        st.o03 AS staff_last_name,
        COUNT(*) AS staff_payment_count
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06),
        st.o01,
        st.o02,
        st.o03
),
main_staff_ranked AS (
    SELECT
        ms.*,
        ROW_NUMBER() OVER (
            PARTITION BY ms.customer_id, ms.payment_day
            ORDER BY ms.staff_payment_count DESC, ms.staff_id
        ) AS rn
    FROM main_staff ms
),
monthly_ranked AS (
    SELECT
        d.customer_id,
        d.payment_day,
        d.day_sum,
        DENSE_RANK() OVER (
            PARTITION BY d.country_name
            ORDER BY d.day_sum DESC
        ) AS suspicious_rank_in_country
    FROM daily_suspicious_final d
    WHERE (d.flag_sum_gt_3std = 1 OR d.flag_count_growth = 1)
)
SELECT
    d.customer_id,
    d.country_name,
    d.city_name,
    d.payment_day,
    ROUND(d.day_sum, 2) AS day_sum,
    d.day_payment_count,
    ROUND(d.mean_sum_prev_30d, 2) AS mean_sum_prev_30d,
    ROUND(d.std_sum_prev_30d, 2) AS std_sum_prev_30d,
    d.obs_days_prev_30d,
    d.flag_sum_gt_3std,
    d.flag_count_growth,
    ROUND(d.non_home_payment_sum_share, 4) AS non_home_payment_sum_share,
    /* most frequent staff */
    ms.staff_id AS main_staff_id,
    ms.staff_first_name,
    ms.staff_last_name,
    /* main category */
    dc.main_category,
    mr.suspicious_rank_in_country
FROM daily_suspicious_final d
JOIN customer_geo cg
  ON cg.customer_id = d.customer_id
LEFT JOIN main_staff_ranked ms
  ON ms.customer_id = d.customer_id
 AND ms.payment_day = d.payment_day
 AND ms.rn = 1
LEFT JOIN daily_category dc
  ON dc.customer_id = d.customer_id
 AND dc.payment_day = d.payment_day
LEFT JOIN monthly_ranked mr
  ON mr.customer_id = d.customer_id
 AND mr.payment_day = d.payment_day
WHERE
    d.obs_days_prev_30d >= 15
    AND (d.flag_sum_gt_3std = 1 OR d.flag_count_growth = 1)
ORDER BY
    d.country_name,
    mr.suspicious_rank_in_country,
    d.day_sum DESC,
    d.customer_id,
    d.payment_day;