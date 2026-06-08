WITH payment_dates AS (
    SELECT
        p02 AS customer_id,
        date(p06) AS payment_date
    FROM pay
    GROUP BY p02, date(p06)
),
rolling_7 AS (
    SELECT
        pd.customer_id,
        pd.payment_date,
        (
            SELECT SUM(p.p05)
            FROM pay AS p
            WHERE p.p02 = pd.customer_id
              AND p.p06 >= datetime(pd.payment_date, '-6 days')
              AND p.p06 <  datetime(pd.payment_date, '+1 day')
        ) AS window_sum_7d,
        (
            SELECT COUNT(*)
            FROM pay AS p
            WHERE p.p02 = pd.customer_id
              AND p.p06 >= datetime(pd.payment_date, '-6 days')
              AND p.p06 <  datetime(pd.payment_date, '+1 day')
        ) AS window_count_7d
    FROM payment_dates AS pd
),
with_history AS (
    SELECT
        r.customer_id,
        r.payment_date,
        r.window_sum_7d,
        r.window_count_7d,
        (
            SELECT AVG(rp.window_sum_7d)
            FROM rolling_7 AS rp
            WHERE rp.customer_id = r.customer_id
              AND rp.payment_date >= date(r.payment_date, '-36 days')
              AND rp.payment_date <  date(r.payment_date, '-6 days')
        ) AS avg_prev30_window_sum_7d,
        (
            SELECT AVG(rp.window_count_7d)
            FROM rolling_7 AS rp
            WHERE rp.customer_id = r.customer_id
              AND rp.payment_date >= date(r.payment_date, '-36 days')
              AND rp.payment_date <  date(r.payment_date, '-6 days')
        ) AS avg_prev30_window_count_7d
    FROM rolling_7 AS r
),
flagged_windows AS (
    SELECT
        customer_id,
        date(payment_date, '-6 days') AS window_start_date,
        payment_date AS window_end_date,
        date(payment_date, '+1 day') AS window_end_exclusive,
        window_sum_7d,
        window_count_7d,
        avg_prev30_window_sum_7d,
        avg_prev30_window_count_7d
    FROM with_history
    WHERE avg_prev30_window_sum_7d IS NOT NULL
      AND avg_prev30_window_sum_7d > 0
      AND window_count_7d >= 5
      AND window_sum_7d >= 3 * avg_prev30_window_sum_7d
),
flagged_payments AS (
    SELECT DISTINCT
        f.customer_id,
        p.p01 AS payment_id,
        p.p05 AS payment_amount
    FROM flagged_windows AS f
    JOIN pay AS p
      ON p.p02 = f.customer_id
     AND p.p06 >= datetime(f.window_start_date)
     AND p.p06 <  datetime(f.window_end_exclusive)
),
customer_suspicious_totals AS (
    SELECT
        customer_id,
        SUM(payment_amount) AS total_suspicious_payment_sum
    FROM flagged_payments
    GROUP BY customer_id
),
ranked_customers AS (
    SELECT
        customer_id,
        total_suspicious_payment_sum,
        DENSE_RANK() OVER (
            ORDER BY total_suspicious_payment_sum DESC
        ) AS suspicious_payment_sum_rank
    FROM customer_suspicious_totals
),
window_details AS (
    SELECT
        f.customer_id,
        f.window_start_date,
        f.window_end_date,
        f.window_sum_7d,
        f.window_count_7d,
        f.avg_prev30_window_sum_7d,
        f.avg_prev30_window_count_7d,
        GROUP_CONCAT(DISTINCT st.o02 || ' ' || st.o03 || ' (#' || st.o01 || ')') AS payment_staff,
        GROUP_CONCAT(DISTINCT 'store #' || sto.j01) AS payment_stores,
        COUNT(DISTINCT inv.n02) AS distinct_rented_films
    FROM flagged_windows AS f
    JOIN pay AS p
      ON p.p02 = f.customer_id
     AND p.p06 >= datetime(f.window_start_date)
     AND p.p06 <  datetime(f.window_end_exclusive)
    JOIN stf AS st
      ON st.o01 = p.p03
    LEFT JOIN sto
      ON sto.j01 = st.o07
    LEFT JOIN ren
      ON ren.q01 = p.p04
    LEFT JOIN inv
      ON inv.n01 = ren.q03
    GROUP BY
        f.customer_id,
        f.window_start_date,
        f.window_end_date,
        f.window_sum_7d,
        f.window_count_7d,
        f.avg_prev30_window_sum_7d,
        f.avg_prev30_window_count_7d
)
SELECT
    rc.suspicious_payment_sum_rank,
    wd.customer_id,
    cus.h03 || ' ' || cus.h04 AS customer_name,
    cty.d02 AS customer_city,
    cnt.c02 AS customer_country,
    wd.window_start_date,
    wd.window_end_date,
    ROUND(wd.window_sum_7d, 2) AS window_sum_7d,
    wd.window_count_7d,
    ROUND(wd.avg_prev30_window_sum_7d, 2) AS avg_prev30_window_sum_7d,
    ROUND(wd.avg_prev30_window_count_7d, 2) AS avg_prev30_window_count_7d,
    ROUND(wd.window_sum_7d / wd.avg_prev30_window_sum_7d, 2) AS sum_spike_ratio,
    wd.payment_staff,
    wd.payment_stores,
    wd.distinct_rented_films,
    ROUND(rc.total_suspicious_payment_sum, 2) AS total_suspicious_payment_sum
FROM window_details AS wd
JOIN ranked_customers AS rc
  ON rc.customer_id = wd.customer_id
JOIN cus
  ON cus.h01 = wd.customer_id
JOIN adr
  ON adr.e01 = cus.h06
JOIN cty
  ON cty.d01 = adr.e05
JOIN cnt
  ON cnt.c01 = cty.d03
ORDER BY
    rc.suspicious_payment_sum_rank,
    rc.total_suspicious_payment_sum DESC,
    wd.window_sum_7d DESC,
    wd.customer_id,
    wd.window_end_date;