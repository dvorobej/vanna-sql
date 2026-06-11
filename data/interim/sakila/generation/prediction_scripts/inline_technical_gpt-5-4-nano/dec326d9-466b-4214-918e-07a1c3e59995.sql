WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS day_start,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(p.p01) AS day_payment_count
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06)
),
win_7d AS (
    SELECT
        customer_id,
        day_start AS window_end_date,
        SUM(day_amount) AS amount_7d,
        SUM(day_payment_count) AS payment_count_7d
    FROM pay_daily
    GROUP BY customer_id, day_start
),
win_7d_with_history AS (
    SELECT
        w.customer_id,
        w.window_end_date,
        w.amount_7d,
        w.payment_count_7d,

        (
            SELECT AVG(w2.amount_7d)
            FROM win_7d AS w2
            WHERE w2.customer_id = w.customer_id
              AND w2.window_end_date >= date(w.window_end_date, '-37 days')
              AND w2.window_end_date <  date(w.window_end_date, '-7 days')
        ) AS avg_amount_prev_30d,

        (
            SELECT AVG(w2.payment_count_7d)
            FROM win_7d AS w2
            WHERE w2.customer_id = w.customer_id
              AND w2.window_end_date >= date(w.window_end_date, '-37 days')
              AND w2.window_end_date <  date(w.window_end_date, '-7 days')
        ) AS avg_payment_count_prev_30d
    FROM win_7d AS w
),
qualifying_windows AS (
    SELECT
        customer_id,
        window_end_date,
        date(window_end_date, '-6 days') AS window_start_date,
        amount_7d,
        payment_count_7d,
        avg_amount_prev_30d,
        avg_payment_count_prev_30d,
        amount_7d / NULLIF(avg_amount_prev_30d, 0) AS amount_multiplier
    FROM win_7d_with_history
    WHERE avg_amount_prev_30d IS NOT NULL
      AND avg_amount_prev_30d > 0
      AND amount_7d >= 3.0 * avg_amount_prev_30d
      AND payment_count_7d >= 5
),
window_i01_counts AS (
    SELECT
        qw.customer_id,
        qw.window_end_date,
        COUNT(DISTINCT i.n02) AS distinct_i01_count_in_window
    FROM qualifying_windows AS qw
    JOIN pay AS p
        ON p.p02 = qw.customer_id
       AND date(p.p06) >= qw.window_start_date
       AND date(p.p06) <= qw.window_end_date
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    GROUP BY
        qw.customer_id,
        qw.window_end_date
),
window_details AS (
    SELECT
        qw.customer_id,
        qw.window_start_date,
        qw.window_end_date,
        qw.amount_7d AS suspicious_amount_7d,
        qw.payment_count_7d AS suspicious_payment_count_7d,

        adr.e01 AS customer_address_id,
        cty.d01 AS customer_city_id,
        cnt.c01 AS customer_country_id,
        cty.d02 AS customer_city_name,
        cnt.c02 AS customer_country_name,

        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        wi.distinct_i01_count_in_window
    FROM qualifying_windows AS qw
    JOIN pay AS p
        ON p.p02 = qw.customer_id
       AND date(p.p06) >= qw.window_start_date
       AND date(p.p06) <= qw.window_end_date
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr
        ON adr.e01 = c.h06
    JOIN cty
        ON cty.d01 = adr.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN window_i01_counts AS wi
        ON wi.customer_id = qw.customer_id
       AND wi.window_end_date = qw.window_end_date
    GROUP BY
        qw.customer_id,
        qw.window_start_date,
        qw.window_end_date,
        qw.amount_7d,
        qw.payment_count_7d,
        adr.e01,
        cty.d01,
        cnt.c01,
        cty.d02,
        cnt.c02,
        wi.distinct_i01_count_in_window
),
ranked AS (
    SELECT
        wd.*,
        DENSE_RANK() OVER (
            ORDER BY wd.suspicious_amount_7d DESC
        ) AS suspicious_rank_by_amount
    FROM window_details wd
)
SELECT
    r.suspicious_rank_by_amount,
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    r.customer_country_name,
    r.customer_city_name,
    r.window_start_date,
    r.window_end_date,
    r.suspicious_payment_count_7d,
    ROUND(r.suspicious_amount_7d, 2) AS suspicious_amount_7d,
    r.distinct_staff_count,
    r.distinct_store_count,
    r.distinct_i01_count_in_window
FROM ranked r
JOIN cus c
    ON c.h01 = r.customer_id
ORDER BY
    r.suspicious_rank_by_amount,
    r.suspicious_amount_7d DESC,
    r.customer_id,
    r.window_end_date;