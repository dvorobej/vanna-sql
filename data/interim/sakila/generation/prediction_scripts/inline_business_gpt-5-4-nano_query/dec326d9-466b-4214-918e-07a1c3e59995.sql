WITH
payments_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_day,
        c.h02 AS home_store_id,
        cnt.c02 AS country_name,
        ctg.d02 AS city_name
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ctg
        ON ctg.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = ctg.d03
),
win AS (
    SELECT
        pe.*,
        SUM(pe2.payment_amount) AS window_sum_7d,
        COUNT(pe2.payment_id) AS window_payment_count_7d
    FROM payments_enriched pe
    JOIN payments_enriched pe2
        ON pe2.customer_id = pe.customer_id
       AND pe2.payment_ts > pe.payment_ts
       AND pe2.payment_ts <= datetime(pe.payment_ts, '+7 days')
    GROUP BY
        pe.payment_id
),
hist AS (
    SELECT
        pe.payment_id,
        AVG(h.payment_amount) AS hist_avg_amount_per_payment,
        AVG(h.payment_count) AS hist_avg_payments_per_day,
        AVG(h.hist_sum) AS hist_avg_sum_per_day,
        AVG(h.hist_cnt) AS hist_avg_cnt_per_day
    FROM payments_enriched pe
    LEFT JOIN (
        SELECT
            p3.p01 AS payment_id,
            p3.p02 AS customer_id,
            date(p3.p06) AS day,
            SUM(CAST(p3.p05 AS REAL)) AS hist_sum,
            COUNT(p3.p01) AS hist_cnt,
            COUNT(p3.p01) AS payment_count,
            CAST(p3.p05 AS REAL) AS payment_amount
        FROM pay p3
        GROUP BY
            p3.p01,
            p3.p02,
            date(p3.p06)
    ) h
        ON h.customer_id = pe.customer_id
       AND date(h.day) >= date(pe.payment_day, '-30 days')
       AND date(h.day) < pe.payment_day
    GROUP BY
        pe.payment_id
),
window_agg AS (
    SELECT
        pe.payment_id,
        pe.customer_id,
        pe.country_name,
        pe.city_name,
        pe.home_store_id,
        pe.payment_ts,
        pe.payment_day,
        w.window_sum_7d,
        w.window_payment_count_7d
    FROM payments_enriched pe
    JOIN win w
        ON w.payment_id = pe.payment_id
),
window_breakdown AS (
    SELECT
        wa.payment_id,
        COUNT(DISTINCT wa.staff_id) AS distinct_staff_count_in_7d,
        COUNT(DISTINCT wa2.home_store_id) AS distinct_stores_count_in_7d,
        COUNT(DISTINCT fc.l02) AS distinct_movie_categories_count_in_7d,
        COUNT(DISTINCT i.n01) AS distinct_rented_films_count_in_7d,
        MAX(CASE WHEN s.o07 <> wa.home_store_id THEN 1 ELSE 0 END) AS has_off_home_staff
    FROM window_agg wa
    JOIN payments_enriched wa2
        ON wa2.customer_id = wa.customer_id
       AND wa2.payment_ts > wa.payment_ts
       AND wa2.payment_ts <= datetime(wa.payment_ts, '+7 days')
    JOIN stf s
        ON s.o01 = wa2.staff_id
    LEFT JOIN ren r
        ON r.q01 = wa2.rental_id
    LEFT JOIN inv i
        ON i.n01 = r.q03
    LEFT JOIN flc fc
        ON fc.l01 = i.n02
    GROUP BY
        wa.payment_id
),
risk_rank AS (
    SELECT
        wa.payment_id,
        wa.customer_id,
        wa.window_sum_7d,
        RANK() OVER (ORDER BY wa.window_sum_7d DESC) AS suspicious_customer_rank_by_sum
    FROM window_agg wa
)
SELECT
    wa.customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    wa.country_name AS country,
    wa.city_name AS city,
    wa.payment_day AS window_start_day,
    ROUND(wa.window_sum_7d, 2) AS window_sum_7d,
    wa.window_payment_count_7d AS window_payment_count_7d,
    rb.distinct_staff_count_in_7d AS distinct_staff_count_in_window,
    rb.distinct_stores_count_in_7d AS distinct_stores_count_in_window,
    rb.distinct_movie_categories_count_in_7d AS distinct_movie_categories_count_in_window,
    rb.has_off_home_staff AS has_off_home_staff_in_window,
    rr.suspicious_customer_rank_by_sum AS suspicious_customer_rank
FROM window_agg wa
JOIN cus c
    ON c.h01 = wa.customer_id
LEFT JOIN window_breakdown rb
    ON rb.payment_id = wa.payment_id
JOIN risk_rank rr
    ON rr.payment_id = wa.payment_id
WHERE
    wa.window_payment_count_7d >= 5
    AND wa.window_sum_7d >= (
        3 * (
            SELECT
                AVG(CAST(p4.p05 AS REAL)) * 5
            FROM pay p4
            WHERE p4.p02 = wa.customer_id
              AND date(p4.p06) >= date(wa.payment_day, '-30 days')
              AND date(p4.p06) < wa.payment_day
        )
    )
ORDER BY
    wa.window_sum_7d DESC,
    wa.customer_id;