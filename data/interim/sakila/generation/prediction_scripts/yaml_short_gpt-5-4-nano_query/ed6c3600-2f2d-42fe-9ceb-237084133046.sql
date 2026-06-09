WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS payment_sum
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_stats AS (
    SELECT
        dp.*,
        AVG(dp.payment_sum) OVER (
            PARTITION BY dp.customer_id
            ORDER BY dp.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_sum_prev_30d,
        /* population stddev: sqrt(E[x^2] - (E[x])^2) */
        sqrt(
            AVG(dp.payment_sum * dp.payment_sum) OVER (
                PARTITION BY dp.customer_id
                ORDER BY dp.payment_day
                ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
            )
            -
            (
                AVG(dp.payment_sum) OVER (
                    PARTITION BY dp.customer_id
                    ORDER BY dp.payment_day
                    ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
                )
                *
                AVG(dp.payment_sum) OVER (
                    PARTITION BY dp.customer_id
                    ORDER BY dp.payment_day
                    ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
                )
            )
        ) AS std_sum_prev_30d,

        AVG(dp.payment_count * 1.0) OVER (
            PARTITION BY dp.customer_id
            ORDER BY dp.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_cnt_prev_30d,
        sqrt(
            AVG(dp.payment_count * dp.payment_count * 1.0) OVER (
                PARTITION BY dp.customer_id
                ORDER BY dp.payment_day
                ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
            )
            -
            (
                AVG(dp.payment_count * 1.0) OVER (
                    PARTITION BY dp.customer_id
                    ORDER BY dp.payment_day
                    ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
                )
                *
                AVG(dp.payment_count * 1.0) OVER (
                    PARTITION BY dp.customer_id
                    ORDER BY dp.payment_day
                    ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
                )
            )
        ) AS std_cnt_prev_30d,

        COUNT(*) OVER (
            PARTITION BY dp.customer_id
            ORDER BY dp.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS hist_days_prev_30d
    FROM daily_payments AS dp
),
flagged_days AS (
    SELECT
        dws.*,
        CASE
            WHEN dws.hist_days_prev_30d >= 30
             AND dws.std_sum_prev_30d IS NOT NULL
             AND dws.std_sum_prev_30d > 0
             AND dws.payment_sum > dws.avg_sum_prev_30d + 3.0 * dws.std_sum_prev_30d
            THEN 1 ELSE 0
        END AS sum_is_anomalous,
        CASE
            WHEN dws.hist_days_prev_30d >= 30
             AND dws.std_cnt_prev_30d IS NOT NULL
             AND dws.std_cnt_prev_30d > 0
             AND dws.payment_count > dws.avg_cnt_prev_30d + 3.0 * dws.std_cnt_prev_30d
            THEN 1 ELSE 0
        END AS count_is_anomalous
    FROM daily_with_stats AS dws
),
base_details AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        p.p05 AS payment_amount,
        s.o07 AS staff_store_id,
        c.h02 AS home_store_id
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN cus AS c ON c.h01 = p.p02
    WHERE p.p06 IS NOT NULL
),
staff_day_share AS (
    SELECT
        bd.customer_id,
        bd.payment_day,
        SUM(CASE WHEN bd.staff_store_id <> bd.home_store_id THEN 1 ELSE 0 END) AS off_home_pay_count,
        COUNT(*) AS total_pay_count,
        ROUND(
            1.0 * SUM(CASE WHEN bd.staff_store_id <> bd.home_store_id THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0),
            4
        ) AS off_home_pay_share
    FROM base_details AS bd
    GROUP BY
        bd.customer_id,
        bd.payment_day
),
top_staff_day AS (
    SELECT
        bd.customer_id,
        bd.payment_day,
        bd.staff_id,
        COUNT(*) AS staff_pay_count,
        SUM(bd.payment_amount) AS staff_pay_sum,
        ROW_NUMBER() OVER (
            PARTITION BY bd.customer_id, bd.payment_day
            ORDER BY SUM(bd.payment_amount) DESC, COUNT(*) DESC, bd.staff_id
        ) AS rn
    FROM base_details AS bd
    GROUP BY
        bd.customer_id,
        bd.payment_day,
        bd.staff_id
),
film_category_day AS (
    SELECT
        r.q04 AS customer_id,
        date(pay.p06) AS payment_day,
        ca.g02 AS category_name,
        COUNT(*) AS rentals_with_category
    FROM pay
    JOIN ren r
      ON r.q01 = pay.p04
    JOIN inv i
      ON i.n01 = r.q03
    JOIN flc fc
      ON fc.l01 = i.n02
    JOIN cat ca
      ON ca.g01 = fc.l02
    WHERE pay.p04 IS NOT NULL
      AND pay.p06 IS NOT NULL
    GROUP BY
        r.q04,
        date(pay.p06),
        ca.g02
),
top_category_day AS (
    SELECT
        fcd.customer_id,
        fcd.payment_day,
        fcd.category_name,
        ROW_NUMBER() OVER (
            PARTITION BY fcd.customer_id, fcd.payment_day
            ORDER BY fcd.rentals_with_category DESC, fcd.category_name
        ) AS rn
    FROM film_category_day AS fcd
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cn.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
)
SELECT
    fd.customer_id,
    cg.country_name,
    cg.city_name,
    fd.payment_day,
    fd.payment_count,
    ROUND(fd.payment_sum, 2) AS payment_sum,
    ROUND(fd.avg_sum_prev_30d, 2) AS avg_sum_prev_30d,
    ROUND(fd.std_sum_prev_30d, 2) AS std_sum_prev_30d,
    ROUND(fd.avg_cnt_prev_30d, 2) AS avg_cnt_prev_30d,
    ROUND(fd.std_cnt_prev_30d, 2) AS std_cnt_prev_30d,
    fd.sum_is_anomalous,
    fd.count_is_anomalous,
    COALESCE(sd.off_home_pay_share, 0.0) AS off_home_staff_payment_share,
    ts.staff_id AS most_frequent_staff_id,
    st.o02 || ' ' || st.o03 AS most_frequent_staff_name,
    tcat.category_name AS top_rented_category,
    /* risk score and ranking */
    (fd.sum_is_anomalous * 2 + fd.count_is_anomalous * 1) AS risk_score
FROM flagged_days AS fd
LEFT JOIN customer_geo AS cg
  ON cg.customer_id = fd.customer_id
LEFT JOIN staff_day_share AS sd
  ON sd.customer_id = fd.customer_id
 AND sd.payment_day = fd.payment_day
LEFT JOIN top_staff_day AS ts
  ON ts.customer_id = fd.customer_id
 AND ts.payment_day = fd.payment_day
 AND ts.rn = 1
LEFT JOIN stf AS st
  ON st.o01 = ts.staff_id
LEFT JOIN top_category_day AS tcat
  ON tcat.customer_id = fd.customer_id
 AND tcat.payment_day = fd.payment_day
 AND tcat.rn = 1
WHERE fd.hist_days_prev_30d >= 30
  AND (fd.sum_is_anomalous = 1 OR fd.count_is_anomalous = 1)
ORDER BY
  risk_score DESC,
  fd.payment_sum DESC,
  fd.payment_count DESC,
  fd.customer_id,
  fd.payment_day;