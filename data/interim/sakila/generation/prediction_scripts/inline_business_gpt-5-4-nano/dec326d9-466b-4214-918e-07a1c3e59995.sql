WITH pay_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        cnt.c02 AS country_name,
        ct.d02 AS city_name,
        p.p03 AS staff_id,
        st.o07 AS home_store_id,
        s.o01 AS store_staff_id,
        p.p04 AS rental_id,
        i.n02 AS film_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        DATE(p.p06) AS payment_day
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ct.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN stf AS st
        ON st.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
),
window_calc AS (
    SELECT
        pb.customer_id,
        pb.customer_first_name,
        pb.customer_last_name,
        pb.country_name,
        pb.city_name,
        pb.payment_day,
        SUM(pb2.payment_amount) AS window_payment_sum,
        COUNT(pb2.payment_id) AS window_payment_count,
        COUNT(DISTINCT pb2.staff_id) AS window_distinct_staff_count,
        COUNT(DISTINCT COALESCE(inv2.n02, -1)) AS window_distinct_film_count,
        COUNT(DISTINCT COALESCE(stf2.o07, -1)) AS window_distinct_store_count
    FROM pay_base AS pb
    JOIN pay_base AS pb2
        ON pb2.customer_id = pb.customer_id
       AND pb2.payment_day >= pb.payment_day
       AND pb2.payment_day < date(pb.payment_day, '+7 day')
    LEFT JOIN ren AS r2
        ON r2.q01 = pb2.rental_id
    LEFT JOIN inv AS inv2
        ON inv2.n01 = r2.q03
    LEFT JOIN stf AS stf2
        ON stf2.o01 = pb2.staff_id
    GROUP BY
        pb.customer_id,
        pb.customer_first_name,
        pb.customer_last_name,
        pb.country_name,
        pb.city_name,
        pb.payment_day
),
history_calc AS (
    SELECT
        wc.*,
        (
            SELECT AVG(hist.payment_sum_avg)
            FROM (
                SELECT
                    DATE(pb3.payment_day) AS hist_day,
                    SUM(pb3.payment_amount) AS payment_sum_avg,
                    COUNT(pb3.payment_id) AS payment_count_avg
                FROM pay_base AS pb3
                WHERE pb3.customer_id = wc.customer_id
                  AND pb3.payment_day >= date(wc.payment_day, '-30 day')
                  AND pb3.payment_day < wc.payment_day
                GROUP BY DATE(pb3.payment_day)
            ) AS hist
        ) AS hist_avg_daily_payment_sum,
        (
            SELECT AVG(hist_cnt.payment_count_avg)
            FROM (
                SELECT
                    DATE(pb4.payment_day) AS hist_day,
                    COUNT(pb4.payment_id) AS payment_count_avg
                FROM pay_base AS pb4
                WHERE pb4.customer_id = wc.customer_id
                  AND pb4.payment_day >= date(wc.payment_day, '-30 day')
                  AND pb4.payment_day < wc.payment_day
                GROUP BY DATE(pb4.payment_day)
            ) AS hist_cnt
        ) AS hist_avg_daily_payment_count
    FROM window_calc AS wc
),
scored AS (
    SELECT
        hc.*,
        CASE
            WHEN hc.hist_avg_daily_payment_sum IS NULL OR hc.hist_avg_daily_payment_sum = 0 THEN NULL
            ELSE hc.window_payment_sum / hc.hist_avg_daily_payment_sum
        END AS sum_multiplier,
        CASE
            WHEN hc.hist_avg_daily_payment_count IS NULL OR hc.hist_avg_daily_payment_count = 0 THEN NULL
            ELSE hc.window_payment_count * 1.0 / hc.hist_avg_daily_payment_count
        END AS count_multiplier
    FROM history_calc AS hc
),
qualified AS (
    SELECT
        s.*,
        RANK() OVER (ORDER BY s.window_payment_sum DESC) AS suspicious_window_amount_rank
    FROM scored AS s
    WHERE s.hist_avg_daily_payment_sum IS NOT NULL
      AND s.hist_avg_daily_payment_sum > 0
      AND s.window_payment_count >= 5
      AND s.window_payment_sum >= 3 * s.hist_avg_daily_payment_sum
)
SELECT
    q.customer_id,
    q.customer_first_name,
    q.customer_last_name,
    q.country_name,
    q.city_name,
    q.payment_day AS window_start_day,
    q.window_payment_count,
    ROUND(q.window_payment_sum, 2) AS window_payment_sum,
    q.window_distinct_staff_count,
    q.window_distinct_store_count,
    q.window_distinct_film_count,
    q.suspicious_window_amount_rank
FROM qualified AS q
ORDER BY
    q.country_name,
    q.suspicious_window_amount_rank,
    q.window_payment_sum DESC,
    q.customer_id,
    q.window_start_day;