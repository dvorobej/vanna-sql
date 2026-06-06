WITH
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        city.d02 AS city_name,
        country.c01 AS country_id,
        country.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS city ON city.d01 = a.e05
    JOIN cnt AS country ON country.c01 = city.d03
),
payment_detail AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        COALESCE(inv.n03, stf.o07) AS store_id
    FROM pay AS p
    JOIN stf AS stf ON stf.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS inv ON inv.n01 = r.q03
),
daily_payments AS (
    SELECT
        customer_id,
        payment_date,
        SUM(amount) AS daily_amount,
        COUNT(*) AS daily_payment_count
    FROM payment_detail
    GROUP BY customer_id, payment_date
),
window_7d_amounts AS (
    SELECT
        d.customer_id,
        date(d.payment_date, '-6 days') AS window_start,
        d.payment_date AS window_end,
        SUM(dp.daily_amount) AS window_amount,
        SUM(dp.daily_payment_count) AS payment_count
    FROM daily_payments AS d
    JOIN daily_payments AS dp
        ON dp.customer_id = d.customer_id
       AND dp.payment_date BETWEEN date(d.payment_date, '-6 days') AND d.payment_date
    GROUP BY
        d.customer_id,
        date(d.payment_date, '-6 days'),
        d.payment_date
),
window_7d_staff_store AS (
    SELECT
        d.customer_id,
        date(d.payment_date, '-6 days') AS window_start,
        d.payment_date AS window_end,
        COUNT(DISTINCT p.staff_id) AS staff_count,
        COUNT(DISTINCT p.store_id) AS store_count
    FROM daily_payments AS d
    JOIN payment_detail AS p
        ON p.customer_id = d.customer_id
       AND p.payment_date BETWEEN date(d.payment_date, '-6 days') AND d.payment_date
    GROUP BY
        d.customer_id,
        date(d.payment_date, '-6 days'),
        d.payment_date
),
window_7d AS (
    SELECT
        a.customer_id,
        a.window_start,
        a.window_end,
        a.window_amount,
        a.payment_count,
        s.staff_count,
        s.store_count
    FROM window_7d_amounts AS a
    JOIN window_7d_staff_store AS s
        ON s.customer_id = a.customer_id
       AND s.window_start = a.window_start
       AND s.window_end = a.window_end
),
customer_baseline AS (
    SELECT
        w.*,
        AVG(w.window_amount) OVER (
            PARTITION BY w.customer_id
            ORDER BY w.window_end
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS customer_prev_avg_7d,
        COUNT(*) OVER (
            PARTITION BY w.customer_id
            ORDER BY w.window_end
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_window_count
    FROM window_7d AS w
),
country_windows AS (
    SELECT
        cb.*,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name
    FROM customer_baseline AS cb
    JOIN customer_geo AS cg ON cg.customer_id = cb.customer_id
),
country_distribution AS (
    SELECT
        country_id,
        window_amount,
        CUME_DIST() OVER (
            PARTITION BY country_id
            ORDER BY window_amount
        ) AS country_cume_dist
    FROM country_windows
),
country_p95 AS (
    SELECT
        country_id,
        MIN(window_amount) AS country_p95_7d
    FROM country_distribution
    WHERE country_cume_dist >= 0.95
    GROUP BY country_id
),
scored AS (
    SELECT
        cw.customer_id,
        cw.customer_name,
        cw.country_name,
        cw.city_name,
        cw.window_start,
        cw.window_end,
        cw.window_amount,
        cw.payment_count,
        cw.staff_count,
        cw.store_count,
        cw.customer_prev_avg_7d,
        cp.country_p95_7d,
        (cw.window_amount / NULLIF(cw.customer_prev_avg_7d, 0))
        + (cw.window_amount / NULLIF(cp.country_p95_7d, 0))
        + CASE WHEN cw.staff_count > 1 THEN 0.5 ELSE 0 END
        + CASE WHEN cw.store_count > 1 THEN 0.5 ELSE 0 END AS suspicion_score
    FROM country_windows AS cw
    JOIN country_p95 AS cp ON cp.country_id = cw.country_id
    WHERE cw.previous_window_count >= 3
      AND cw.customer_prev_avg_7d > 0
      AND cw.window_amount >= 2.0 * cw.customer_prev_avg_7d
      AND cw.window_amount >= cp.country_p95_7d
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    window_start,
    window_end,
    ROUND(window_amount, 2) AS window_amount,
    payment_count,
    staff_count,
    store_count,
    ROUND(customer_prev_avg_7d, 2) AS customer_previous_avg_7d,
    ROUND(country_p95_7d, 2) AS country_p95_7d,
    RANK() OVER (
        ORDER BY suspicion_score DESC, window_amount DESC, payment_count DESC
    ) AS suspicion_rank
FROM scored
ORDER BY suspicion_rank, customer_id, window_end;