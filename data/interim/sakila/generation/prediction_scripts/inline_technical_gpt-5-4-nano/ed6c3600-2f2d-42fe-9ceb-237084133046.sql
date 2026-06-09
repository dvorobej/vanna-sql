SELECT AVG(dc2.payment_count)
            FROM daily_customer dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_date >= date(dc.payment_date, '-30 day')
              AND dc2.payment_date < dc.payment_date
        ) AS avg_payment_count_30d,
        (
            SELECT AVG(dc2.day_amount)
            FROM daily_customer dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_date >= date(dc.payment_date, '-30 day')
              AND dc2.payment_date < dc.payment_date
        ) AS avg_day_amount_30d,
        (
            SELECT AVG(
                (dc2.day_amount - (
                    SELECT AVG(dc3.day_amount)
                    FROM daily_customer dc3
                    WHERE dc3.customer_id = dc.customer_id
                      AND dc3.payment_date >= date(dc.payment_date, '-30 day')
                      AND dc3.payment_date < dc.payment_date
                )) * (dc2.day_amount - (
                    SELECT AVG(dc4.day_amount)
                    FROM daily_customer dc4
                    WHERE dc4.customer_id = dc.customer_id
                      AND dc4.payment_date >= date(dc.payment_date, '-30 day')
                      AND dc4.payment_date < dc.payment_date
                ))
            )
            FROM daily_customer dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_date >= date(dc.payment_date, '-30 day')
              AND dc2.payment_date < dc.payment_date
        ) AS var_day_amount_30d,
        (
            SELECT COUNT(*)
            FROM daily_customer dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_date >= date(dc.payment_date, '-30 day')
              AND dc2.payment_date < dc.payment_date
        ) AS history_days
    FROM daily_customer dc
),
anomalies AS (
    SELECT
        dr.customer_id,
        dr.payment_date,
        dr.payment_count,
        dr.day_amount,
        dr.avg_day_amount_30d,
        dr.var_day_amount_30d,
        CASE
            WHEN dr.var_day_amount_30d IS NOT NULL THEN sqrt(dr.var_day_amount_30d)
        END AS std_day_amount_30d,
        dr.avg_payment_count_30d,
        dr.history_days,
        CASE
            WHEN dr.history_days >= 10
             AND dr.var_day_amount_30d IS NOT NULL
             AND dr.day_amount > dr.avg_day_amount_30d + 3 * sqrt(dr.var_day_amount_30d)
            THEN 1 ELSE 0
        END AS amount_anomaly_flag,
        CASE
            WHEN dr.history_days >= 10
             AND dr.avg_payment_count_30d IS NOT NULL
             AND dr.payment_count > dr.avg_payment_count_30d + 3 * sqrt(
                (
                    SELECT AVG(
                        (dc2.payment_count - dr.avg_payment_count_30d) *
                        (dc2.payment_count - dr.avg_payment_count_30d)
                    )
                    FROM daily_customer dc2
                    WHERE dc2.customer_id = dr.customer_id
                      AND dc2.payment_date >= date(dr.payment_date, '-30 day')
                      AND dc2.payment_date < dr.payment_date
                )
             )
            THEN 1 ELSE 0
        END AS count_anomaly_flag
    FROM daily_rolling_stats dr
),
anomaly_days AS (
    SELECT *
    FROM anomalies
    WHERE history_days >= 10
      AND (amount_anomaly_flag = 1 OR count_anomaly_flag = 1)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        c.h02 AS customer_store_id,
        c.h06 AS address_id
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
payments_day_details AS (
    SELECT
        p.customer_id,
        p.payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS day_payment_count
    FROM (
        SELECT
            c.h01 AS customer_id,
            pay.p06 AS payment_date,
            pay.p05 AS p05
        FROM pay
        JOIN cus c ON c.h01 = pay.p02
        WHERE c.h07 = 'Y'
    ) p
    GROUP BY p.customer_id, date(p.payment_date)
),
most_freq_staff AS (
    SELECT
        c.h01 AS customer_id,
        date(pay.p06) AS payment_date,
        pay.p03 AS staff_id,
        COUNT(*) AS staff_payment_count,
        ROW_NUMBER() OVER (
            PARTITION BY c.h01, date(pay.p06)
            ORDER BY COUNT(*) DESC, pay.p03
        ) AS rn
    FROM pay
    JOIN cus c ON c.h01 = pay.p02
    WHERE c.h07 = 'Y'
    GROUP BY c.h01, date(pay.p06), pay.p03
),
main_category AS (
    SELECT
        c.h01 AS customer_id,
        date(pay.p06) AS payment_date,
        cat.g02 AS main_category,
        ROW_NUMBER() OVER (
            PARTITION BY c.h01, date(pay.p06)
            ORDER BY COUNT(*) DESC, cat.g02
        ) AS rn
    FROM pay
    JOIN cus c ON c.h01 = pay.p02
    JOIN ren r ON r.q01 = pay.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flc ON flc.l01 = i.n02
    JOIN cat ON cat.g01 = flc.l02
    WHERE c.h07 = 'Y'
    GROUP BY c.h01, date(pay.p06), cat.g02
),
other_store_share AS (
    SELECT
        c.h01 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CASE WHEN st.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS other_store_payment_share_count,
        SUM(CASE WHEN st.o07 <> c.h02 THEN CAST(p.p05 AS REAL) ELSE 0 END) * 1.0 / SUM(CAST(p.p05 AS REAL)) AS other_store_payment_share_amount
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf st ON st.o01 = p.p03
    WHERE c.h07 = 'Y'
    GROUP BY c.h01, date(p.p06)
)
SELECT
    ad.customer_id AS h01,
    cg.country,
    cg.city,
    ad.payment_date AS p06,
    ROUND(ad.day_amount, 2) AS day_amount,
    ad.payment_count AS day_payment_count,
    ROUND(ad.avg_day_amount_30d, 2) AS avg_day_amount_30d,
    ROUND(ad.std_day_amount_30d, 2) AS std_day_amount_30d,
    ROUND(ad.day_amount - ad.avg_day_amount_30d, 2) AS deviation_amount,
    ROUND(ad.avg_payment_count_30d, 2) AS avg_payment_count_30d,
    os.other_store_payment_share_count AS other_store_payment_share_count,
    os.other_store_payment_share_amount AS other_store_payment_share_amount,
    ms.staff_id AS most_freq_staff_id,
    st.o02 AS most_freq_staff_first_name,
    st.o03 AS most_freq_staff_last_name,
    sto.j01 AS most_freq_staff_store_id,
    mc.main_category AS main_rented_film_category_for_day,
    DENSE_RANK() OVER (
        ORDER BY ad.day_amount DESC
    ) AS risk_rank_overall
FROM anomaly_days ad
JOIN customer_geo cg ON cg.customer_id = ad.customer_id
LEFT JOIN other_store_share os
    ON os.customer_id = ad.customer_id
   AND os.payment_date = ad.payment_date
LEFT JOIN (
    SELECT customer_id, payment_date, staff_id
    FROM most_freq_staff
    WHERE rn = 1
) ms
    ON ms.customer_id = ad.customer_id
   AND ms.payment_date = ad.payment_date
LEFT JOIN stf st ON st.o01 = ms.staff_id
LEFT JOIN sto ON sto.j01 = st.o07
LEFT JOIN (
    SELECT customer_id, payment_date, main_category
    FROM main_category
    WHERE rn = 1
) mc
    ON mc.customer_id = ad.customer_id
   AND mc.payment_date = ad.payment_date
ORDER BY risk_rank_overall, ad.customer_id, ad.payment_date;