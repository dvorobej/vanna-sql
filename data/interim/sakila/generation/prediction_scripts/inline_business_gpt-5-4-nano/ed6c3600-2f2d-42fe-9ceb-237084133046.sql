WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_payment_amount,
        COUNT(DISTINCT CASE WHEN r.q01 IS NOT NULL THEN r.q01 END) AS rented_inventories_count
    FROM pay AS p
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        dcp.*,
        AVG(dcp.day_payment_amount) AS avg_amount_prev30,
        AVG(dcp.payment_count * 1.0) AS avg_count_prev30,
        (AVG(dcp.day_payment_amount * dcp.day_payment_amount) - AVG(dcp.day_payment_amount) * AVG(dcp.day_payment_amount)) AS var_amount_prev30
    FROM daily_customer_payments AS dcp
    WHERE 1=1
    GROUP BY
        dcp.customer_id,
        dcp.payment_date,
        dcp.payment_count,
        dcp.day_payment_amount
),
daily_stats AS (
    SELECT
        dcp.customer_id,
        dcp.payment_date,
        dcp.payment_count,
        dcp.day_payment_amount,
        (
            SELECT AVG(dcp2.day_payment_amount)
            FROM daily_customer_payments AS dcp2
            WHERE dcp2.customer_id = dcp.customer_id
              AND dcp2.payment_date >= date(dcp.payment_date, '-30 days')
              AND dcp2.payment_date < dcp.payment_date
        ) AS avg_amount_prev30,
        (
            SELECT AVG(dcp2.payment_count * 1.0)
            FROM daily_customer_payments AS dcp2
            WHERE dcp2.customer_id = dcp.customer_id
              AND dcp2.payment_date >= date(dcp.payment_date, '-30 days')
              AND dcp2.payment_date < dcp.payment_date
        ) AS avg_count_prev30,
        (
            SELECT
                AVG(dcp2.day_payment_amount * 1.0 * dcp2.day_payment_amount)
                - (AVG(dcp2.day_payment_amount) * AVG(dcp2.day_payment_amount))
            FROM daily_customer_payments AS dcp2
            WHERE dcp2.customer_id = dcp.customer_id
              AND dcp2.payment_date >= date(dcp.payment_date, '-30 days')
              AND dcp2.payment_date < dcp.payment_date
        ) AS var_amount_prev30,
        (
            SELECT COUNT(*)
            FROM daily_customer_payments AS dcp2
            WHERE dcp2.customer_id = dcp.customer_id
              AND dcp2.payment_date >= date(dcp.payment_date, '-30 days')
              AND dcp2.payment_date < dcp.payment_date
        ) AS history_days_count
    FROM daily_customer_payments AS dcp
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS home_store_id,
        cnt.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = ci.d03
),
daily_staff_store_share AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS day_payment_count,
        SUM(
            CASE
                WHEN st.o07 <> c.home_store_id THEN 1
                ELSE 0
            END
        ) AS non_home_store_payment_count,
        SUM(
            CASE
                WHEN st.o07 <> c.home_store_id THEN CAST(p.p05 AS REAL)
                ELSE 0
            END
        ) AS non_home_store_amount
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    JOIN cus AS c ON c.h01 = p.p02
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_top_staff AS (
    SELECT
        customer_id,
        payment_date,
        staff_id,
        staff_amount,
        staff_payment_count,
        RANK() OVER (
            PARTITION BY customer_id, payment_date
            ORDER BY staff_amount DESC, staff_payment_count DESC, staff_id
        ) AS staff_rank
    FROM (
        SELECT
            p.p02 AS customer_id,
            date(p.p06) AS payment_date,
            p.p03 AS staff_id,
            SUM(CAST(p.p05 AS REAL)) AS staff_amount,
            COUNT(*) AS staff_payment_count
        FROM pay AS p
        GROUP BY
            p.p02,
            date(p.p06),
            p.p03
    ) x
),
daily_main_category AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        ca.g02 AS category_name,
        SUM(CAST(p.p05 AS REAL)) AS category_amount,
        DENSE_RANK() OVER (
            PARTITION BY p.p02, date(p.p06)
            ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, ca.g02
        ) AS category_rank
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat AS ca ON ca.g01 = fc.l02
    GROUP BY
        p.p02,
        date(p.p06),
        ca.g02
),
risk_days AS (
    SELECT
        ds.customer_id,
        ds.payment_date,
        ds.payment_count,
        ds.day_payment_amount,
        ds.avg_amount_prev30,
        ds.avg_count_prev30,
        CASE
            WHEN ds.var_amount_prev30 < 0 THEN 0
            ELSE sqrt(ds.var_amount_prev30)
        END AS std_amount_prev30,
        ds.history_days_count
    FROM daily_stats AS ds
    WHERE ds.history_days_count >= 20
)
, flagged_days AS (
    SELECT
        rd.*,
        (rd.day_payment_amount - rd.avg_amount_prev30) AS amount_deviation,
        CASE
            WHEN rd.std_amount_prev30 > 0
             AND rd.day_payment_amount > rd.avg_amount_prev30 + 3 * rd.std_amount_prev30
            THEN 1 ELSE 0
        END AS flag_amount_gt_3std,
        CASE
            WHEN rd.avg_count_prev30 > 0
             AND rd.payment_count >= rd.avg_count_prev30 * 2
            THEN 1 ELSE 0
        END AS flag_count_growth,
        CASE
            WHEN rd.std_amount_prev30 > 0
             AND rd.day_payment_amount > rd.avg_amount_prev30 + 3 * rd.std_amount_prev30
            THEN 1
            WHEN rd.avg_count_prev30 > 0
             AND rd.payment_count >= rd.avg_count_prev30 * 2
            THEN 1
            ELSE 0
        END AS is_suspicious
    FROM risk_days AS rd
    WHERE rd.avg_amount_prev30 IS NOT NULL
      AND rd.avg_amount_prev30 > 0
)
, suspicious_ranked AS (
    SELECT
        fd.*,
        DENSE_RANK() OVER (
            PARTITION BY fd.customer_id
            ORDER BY (fd.day_payment_amount - fd.avg_amount_prev30) DESC, fd.payment_date DESC
        ) AS suspicious_rank_in_customer
    FROM flagged_days AS fd
    WHERE fd.is_suspicious = 1
)
SELECT
    sr.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    sr.payment_date,
    ROUND(sr.day_payment_amount, 2) AS day_payment_amount,
    sr.payment_count,
    ROUND(sr.avg_amount_prev30, 2) AS avg_amount_prev30,
    ROUND(sr.std_amount_prev30, 2) AS std_amount_prev30,
    sr.flag_amount_gt_3std,
    sr.flag_count_growth,
    ROUND(
        CAST(dss.non_home_store_payment_count AS REAL) / NULLIF(dss.day_payment_count, 0),
        4
    ) AS non_home_store_staff_share,
    dss.non_home_store_payment_count AS non_home_store_payment_count,
    dss.day_payment_count AS day_payment_count,
    cg.country_name,
    cg.city_name,
    ts.staff_id AS top_staff_id,
    s2.o02 || ' ' || s2.o03 AS top_staff_name,
    dc.category_name AS main_category,
    dc.category_amount AS main_category_amount,
    sr.suspicious_rank_in_customer
FROM suspicious_ranked AS sr
JOIN cus AS c ON c.h01 = sr.customer_id
LEFT JOIN customer_geo AS cg ON cg.customer_id = sr.customer_id
LEFT JOIN daily_staff_store_share AS dss
    ON dss.customer_id = sr.customer_id
   AND dss.payment_date = sr.payment_date
LEFT JOIN daily_top_staff AS ts
    ON ts.customer_id = sr.customer_id
   AND ts.payment_date = sr.payment_date
   AND ts.staff_rank = 1
LEFT JOIN stf AS s2 ON s2.o01 = ts.staff_id
LEFT JOIN daily_main_category AS dc
    ON dc.customer_id = sr.customer_id
   AND dc.payment_date = sr.payment_date
   AND dc.category_rank = 1
ORDER BY
    sr.customer_id,
    sr.payment_date;