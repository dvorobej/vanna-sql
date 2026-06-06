WITH
base_payments AS (
    SELECT
        p01 AS payment_id,
        p02 AS customer_id,
        p03 AS staff_id,
        CAST(p05 AS REAL) AS amount,
        p06 AS payment_date,
        julianday(p06) AS payment_jd
    FROM pay
),
win_joined AS (
    SELECT
        a.payment_id AS anchor_payment_id,
        a.customer_id,
        a.payment_date AS window_start,
        p.payment_id,
        p.staff_id,
        p.amount,
        p.payment_date,
        COUNT(*) OVER (
            PARTITION BY a.payment_id
        ) AS window_payment_count,
        SUM(p.amount) OVER (
            PARTITION BY a.payment_id
        ) AS window_payment_sum,
        ROW_NUMBER() OVER (
            PARTITION BY a.payment_id
            ORDER BY p.payment_jd DESC, p.payment_id DESC
        ) AS rn_last_payment
    FROM base_payments AS a
    JOIN base_payments AS p
        ON p.customer_id = a.customer_id
       AND p.payment_jd >= a.payment_jd
       AND p.payment_jd <  a.payment_jd + 1
),
window_24h AS (
    SELECT
        anchor_payment_id,
        customer_id,
        window_start,
        datetime(window_start, '+1 day') AS window_end,
        window_payment_count,
        window_payment_sum,
        payment_id AS last_payment_id,
        payment_date AS last_payment_date,
        amount AS last_payment_amount,
        staff_id AS last_staff_id
    FROM win_joined
    WHERE rn_last_payment = 1
),
history_30d AS (
    SELECT
        a.payment_id AS anchor_payment_id,
        COUNT(h.payment_id) AS hist_payment_count,
        COALESCE(SUM(h.amount), 0.0) AS hist_payment_sum
    FROM base_payments AS a
    LEFT JOIN base_payments AS h
        ON h.customer_id = a.customer_id
       AND h.payment_jd >= a.payment_jd - 30
       AND h.payment_jd <  a.payment_jd
    GROUP BY a.payment_id
),
suspicious AS (
    SELECT
        w.*,
        h.hist_payment_count,
        h.hist_payment_sum,
        h.hist_payment_count / 30.0 AS avg_daily_payment_count_30d,
        h.hist_payment_sum / 30.0 AS avg_daily_payment_sum_30d,
        w.window_payment_count * 30.0 / NULLIF(h.hist_payment_count, 0) AS count_ratio_to_norm,
        w.window_payment_sum * 30.0 / NULLIF(h.hist_payment_sum, 0) AS sum_ratio_to_norm,
        MIN(
            w.window_payment_count * 30.0 / NULLIF(h.hist_payment_count, 0),
            w.window_payment_sum * 30.0 / NULLIF(h.hist_payment_sum, 0)
        ) AS deviation_score
    FROM window_24h AS w
    JOIN history_30d AS h
        ON h.anchor_payment_id = w.anchor_payment_id
    WHERE h.hist_payment_count > 0
      AND h.hist_payment_sum > 0
      AND w.window_payment_count >= 3.0 * h.hist_payment_count / 30.0
      AND w.window_payment_sum >= 3.0 * h.hist_payment_sum / 30.0
)
SELECT
    RANK() OVER (
        ORDER BY
            s.deviation_score DESC,
            s.sum_ratio_to_norm DESC,
            s.count_ratio_to_norm DESC,
            s.window_payment_sum DESC
    ) AS suspicion_rank,
    s.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    c.h05 AS customer_email,
    country.c02 AS customer_country,
    city.d02 AS customer_city,
    c.h02 AS customer_store_id,
    store.j01 AS last_payment_store_id,
    s.window_start,
    s.window_end,
    s.window_payment_count,
    ROUND(s.window_payment_sum, 2) AS window_payment_sum,
    s.hist_payment_count,
    ROUND(s.hist_payment_sum, 2) AS hist_payment_sum_30d,
    ROUND(s.avg_daily_payment_count_30d, 4) AS avg_daily_payment_count_30d,
    ROUND(s.avg_daily_payment_sum_30d, 4) AS avg_daily_payment_sum_30d,
    ROUND(s.count_ratio_to_norm, 4) AS count_ratio_to_norm,
    ROUND(s.sum_ratio_to_norm, 4) AS sum_ratio_to_norm,
    ROUND(s.deviation_score, 4) AS deviation_score,
    s.last_payment_id,
    s.last_payment_date,
    ROUND(s.last_payment_amount, 2) AS last_payment_amount,
    staff.o01 AS last_payment_staff_id,
    staff.o02 || ' ' || staff.o03 AS last_payment_staff_name
FROM suspicious AS s
JOIN cus AS c
    ON c.h01 = s.customer_id
JOIN adr AS customer_address
    ON customer_address.e01 = c.h06
JOIN cty AS city
    ON city.d01 = customer_address.e05
JOIN cnt AS country
    ON country.c01 = city.d03
JOIN stf AS staff
    ON staff.o01 = s.last_staff_id
LEFT JOIN sto AS store
    ON store.j01 = staff.o07
ORDER BY
    suspicion_rank,
    s.window_start,
    s.customer_id;