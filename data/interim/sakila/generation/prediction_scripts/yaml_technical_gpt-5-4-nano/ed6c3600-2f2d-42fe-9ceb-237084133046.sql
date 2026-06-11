WITH daily AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS customer_store_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        date(p.p06) AS day_date,
        COUNT(p.p01) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        AVG(CAST(p.p05 AS REAL)) AS daily_avg_payment
    FROM cus AS c
    JOIN pay AS p
        ON p.p02 = c.h01
    WHERE p.p06 IS NOT NULL
    GROUP BY
        c.h01, c.h02, c.h03, c.h04, date(p.p06)
),
history_calc AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.daily_amount)
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.day_date >= date(d.day_date, '-30 day')
              AND d2.day_date < d.day_date
        ) AS avg_daily_amount_prev_30d,
        (
            SELECT AVG(d2.payment_count)
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.day_date >= date(d.day_date, '-30 day')
              AND d2.day_date < d.day_date
        ) AS avg_payment_count_prev_30d,
        (
            SELECT
                CASE
                    WHEN COUNT(*) < 2 THEN NULL
                    ELSE
                        sqrt(AVG(d2.daily_amount * d2.daily_amount) - AVG(d2.daily_amount) * AVG(d2.daily_amount))
                END
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.day_date >= date(d.day_date, '-30 day')
              AND d2.day_date < d.day_date
        ) AS std_daily_amount_prev_30d,
        (
            SELECT
                CASE
                    WHEN COUNT(*) < 2 THEN NULL
                    ELSE
                        sqrt(AVG(d2.payment_count * d2.payment_count) - AVG(d2.payment_count) * AVG(d2.payment_count))
                END
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.day_date >= date(d.day_date, '-30 day')
              AND d2.day_date < d.day_date
        ) AS std_payment_count_prev_30d,
        (
            SELECT COUNT(*)
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.day_date >= date(d.day_date, '-30 day')
              AND d2.day_date < d.day_date
        ) AS history_days_count
    FROM daily AS d
),
flags AS (
    SELECT
        hc.*,
        CASE
            WHEN hc.std_daily_amount_prev_30d IS NOT NULL
             AND hc.avg_daily_amount_prev_30d IS NOT NULL
             AND hc.daily_amount > hc.avg_daily_amount_prev_30d + 3 * hc.std_daily_amount_prev_30d
                THEN 1 ELSE 0
        END AS flag_amount_gt_3std,
        CASE
            WHEN hc.std_payment_count_prev_30d IS NOT NULL
             AND hc.avg_payment_count_prev_30d IS NOT NULL
             AND hc.payment_count > hc.avg_payment_count_prev_30d + 3 * hc.std_payment_count_prev_30d
                THEN 1 ELSE 0
        END AS flag_count_gt_3std,
        CASE
            WHEN hc.avg_daily_amount_prev_30d IS NOT NULL AND hc.avg_daily_amount_prev_30d > 0
                THEN (hc.daily_amount - hc.avg_daily_amount_prev_30d) / hc.avg_daily_amount_prev_30d
            ELSE NULL
        END AS deviation_ratio_amount,
        CASE
            WHEN hc.avg_payment_count_prev_30d IS NOT NULL AND hc.avg_payment_count_prev_30d > 0
                THEN (hc.payment_count - hc.avg_payment_count_prev_30d) / hc.avg_payment_count_prev_30d
            ELSE NULL
        END AS deviation_ratio_count
    FROM history_calc AS hc
    WHERE hc.history_days_count >= 30
),
non_customer_store_share AS (
    SELECT
        c.h01 AS customer_id,
        date(p.p06) AS day_date,
        SUM(CASE WHEN stf.o07 <> c.h02 THEN CAST(p.p05 AS REAL) ELSE 0 END) AS amount_from_other_stores,
        SUM(CAST(p.p05 AS REAL)) AS amount_total,
        CASE
            WHEN SUM(CAST(p.p05 AS REAL)) > 0
                THEN 1.0 * SUM(CASE WHEN stf.o07 <> c.h02 THEN CAST(p.p05 AS REAL) ELSE 0 END)
                     / SUM(CAST(p.p05 AS REAL))
            ELSE NULL
        END AS other_store_share
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN stf
        ON stf.o01 = p.p03
    GROUP BY
        c.h01, date(p.p06)
),
day_top_staff AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS day_date,
        p.p03 AS staff_id,
        SUM(CAST(p.p05 AS REAL)) AS staff_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, date(p.p06)
            ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, COUNT(*) DESC, p.p03
        ) AS rn
    FROM pay AS p
    GROUP BY
        p.p02, date(p.p06), p.p03
),
day_main_category AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS day_date,
        cat.g02 AS category_id,
        SUM(CAST(p.p05 AS REAL)) AS category_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, date(p.p06)
            ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, cat.g02
        ) AS rn
    FROM pay AS p
    JOIN ren
        ON ren.q01 = p.p04
    JOIN inv
        ON inv.n01 = ren.q03
    JOIN flc
        ON flc.l01 = inv.n02
    JOIN cat
        ON cat.g01 = flc.l02
    GROUP BY
        p.p02, date(p.p06), cat.g02
)
SELECT
    f.customer_id AS h01,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    f.day_date AS p06_day,
    ROUND(f.daily_amount, 2) AS daily_amount,
    f.payment_count,
    ROUND(f.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
    ROUND(f.std_daily_amount_prev_30d, 2) AS std_daily_amount_prev_30d,
    ROUND(f.avg_payment_count_prev_30d, 2) AS avg_payment_count_prev_30d,
    ROUND(f.std_payment_count_prev_30d, 2) AS std_payment_count_prev_30d,
    f.flag_amount_gt_3std,
    f.flag_count_gt_3std,
    ROUND(f.deviation_ratio_amount, 4) AS deviation_ratio_amount,
    ROUND(f.deviation_ratio_count, 4) AS deviation_ratio_count,
    ROUND(ncs.other_store_share, 4) AS other_store_share_amount,
    ts.o01 AS top_staff_id,
    ts.o02 AS top_staff_first_name,
    ts.o03 AS top_staff_last_name,
    sto.j01 AS top_staff_store_id,
    dmc.category_id AS main_category_id,
    CASE
        WHEN (f.flag_amount_gt_3std = 1 AND f.flag_count_gt_3std = 1) THEN 3
        WHEN (f.flag_amount_gt_3std = 1 OR f.flag_count_gt_3std = 1) THEN 2
        ELSE 1
    END AS risk_level,
    DENSE_RANK() OVER (
        PARTITION BY cnt.c01
        ORDER BY
            (f.flag_amount_gt_3std * 3 + f.flag_count_gt_3std * 2) DESC,
            f.daily_amount DESC
    ) AS suspicion_rank_in_country
FROM flags AS f
JOIN cus AS c
    ON c.h01 = f.customer_id
JOIN adr
    ON adr.e01 = c.h06
JOIN cty
    ON cty.d01 = adr.e05
JOIN cnt
    ON cnt.c01 = cty.d03
LEFT JOIN non_customer_store_share AS ncs
    ON ncs.customer_id = f.customer_id
   AND ncs.day_date = f.day_date
LEFT JOIN day_top_staff AS dts
    ON dts.customer_id = f.customer_id
   AND dts.day_date = f.day_date
   AND dts.rn = 1
LEFT JOIN stf AS ts
    ON ts.o01 = dts.staff_id
LEFT JOIN sto
    ON sto.j01 = ts.o07
LEFT JOIN day_main_category AS dmc
    ON dmc.customer_id = f.customer_id
   AND dmc.day_date = f.day_date
   AND dmc.rn = 1
WHERE (f.flag_amount_gt_3std = 1 OR f.flag_count_gt_3std = 1)
ORDER BY
    suspicion_rank_in_country,
    f.daily_amount DESC,
    f.customer_id,
    f.day_date;