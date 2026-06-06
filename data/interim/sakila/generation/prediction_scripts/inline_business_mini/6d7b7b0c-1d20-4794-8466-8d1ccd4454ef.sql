WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS amount,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_day
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        ct.d02 AS city_name,
        cn.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
),
customers AS (
    SELECT DISTINCT customer_id
    FROM payment_base
),
calendar AS (
    SELECT MIN(payment_day) AS start_day, MAX(payment_day) AS end_day
    FROM payment_base
),
window_starts AS (
    SELECT
        c.customer_id,
        date(p.payment_day, '+' || n.n || ' hours') AS window_start
    FROM customers AS c
    JOIN payment_base AS p
        ON p.customer_id = c.customer_id
    CROSS JOIN (
        SELECT 0 AS n
        UNION ALL SELECT 1
        UNION ALL SELECT 2
        UNION ALL SELECT 3
        UNION ALL SELECT 4
        UNION ALL SELECT 5
        UNION ALL SELECT 6
        UNION ALL SELECT 7
        UNION ALL SELECT 8
        UNION ALL SELECT 9
        UNION ALL SELECT 10
        UNION ALL SELECT 11
        UNION ALL SELECT 12
        UNION ALL SELECT 13
        UNION ALL SELECT 14
        UNION ALL SELECT 15
        UNION ALL SELECT 16
        UNION ALL SELECT 17
        UNION ALL SELECT 18
        UNION ALL SELECT 19
        UNION ALL SELECT 20
        UNION ALL SELECT 21
        UNION ALL SELECT 22
        UNION ALL SELECT 23
    ) AS n
),
window_metrics AS (
    SELECT
        ws.customer_id,
        ws.window_start,
        datetime(ws.window_start, '+24 hours') AS window_end,
        COUNT(pb.payment_id) AS window_payment_count,
        SUM(pb.amount) AS window_payment_sum,
        COUNT(DISTINCT pb.staff_id) AS window_staff_count,
        COUNT(DISTINCT pb.store_id) AS window_store_count,
        MAX(pb.payment_ts) AS last_payment_ts
    FROM window_starts AS ws
    JOIN payment_base AS pb
        ON pb.customer_id = ws.customer_id
       AND pb.payment_ts >= ws.window_start
       AND pb.payment_ts < datetime(ws.window_start, '+24 hours')
    GROUP BY
        ws.customer_id,
        ws.window_start
),
window_last_payment AS (
    SELECT
        wm.customer_id,
        wm.window_start,
        pb.payment_id AS last_payment_id,
        pb.staff_id AS last_staff_id,
        pb.store_id AS last_store_id
    FROM window_metrics AS wm
    JOIN payment_base AS pb
        ON pb.customer_id = wm.customer_id
       AND pb.payment_ts = wm.last_payment_ts
       AND pb.payment_ts >= wm.window_start
       AND pb.payment_ts < wm.window_end
),
daily_history AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        SUM(pb.amount) AS day_amount,
        COUNT(pb.payment_id) AS day_payment_count
    FROM payment_base AS pb
    GROUP BY
        pb.customer_id,
        pb.payment_day
),
history_stats AS (
    SELECT
        dh.customer_id,
        dh.payment_day,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_history AS prev
            WHERE prev.customer_id = dh.customer_id
              AND prev.payment_day >= date(dh.payment_day, '-30 day')
              AND prev.payment_day < dh.payment_day
        ) AS avg_prev_30d_amount,
        (
            SELECT AVG(prev.day_payment_count)
            FROM daily_history AS prev
            WHERE prev.customer_id = dh.customer_id
              AND prev.payment_day >= date(dh.payment_day, '-30 day')
              AND prev.payment_day < dh.payment_day
        ) AS avg_prev_30d_count
    FROM daily_history AS dh
),
scored_windows AS (
    SELECT
        wm.customer_id,
        wm.window_start,
        wm.window_end,
        wm.window_payment_count,
        wm.window_payment_sum,
        wm.window_staff_count,
        wm.window_store_count,
        wl.last_payment_id,
        wl.last_staff_id,
        wl.last_store_id,
        hs.avg_prev_30d_amount,
        hs.avg_prev_30d_count,
        (wm.window_payment_sum / NULLIF(hs.avg_prev_30d_amount, 0.0)) AS amount_ratio,
        (wm.window_payment_count / NULLIF(hs.avg_prev_30d_count, 0.0)) AS count_ratio,
        (wm.window_payment_sum / NULLIF(hs.avg_prev_30d_amount, 0.0))
        + (wm.window_payment_count / NULLIF(hs.avg_prev_30d_count, 0.0)) AS deviation_score
    FROM window_metrics AS wm
    JOIN window_last_payment AS wl
        ON wl.customer_id = wm.customer_id
       AND wl.window_start = wm.window_start
    JOIN history_stats AS hs
        ON hs.customer_id = wm.customer_id
       AND hs.payment_day = date(wm.window_start)
)
SELECT
    cg.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    sw.window_start,
    sw.window_end,
    ROUND(sw.window_payment_sum, 2) AS window_payment_sum,
    sw.window_payment_count,
    ROUND(sw.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    ROUND(sw.avg_prev_30d_count, 2) AS avg_prev_30d_count,
    sw.window_staff_count,
    sw.window_store_count,
    sw.last_payment_id,
    sw.last_staff_id,
    sw.last_store_id,
    RANK() OVER (
        ORDER BY sw.deviation_score DESC, sw.window_payment_sum DESC
    ) AS deviation_rank
FROM scored_windows AS sw
JOIN customer_geo AS cg
    ON cg.customer_id = sw.customer_id
WHERE sw.avg_prev_30d_amount > 0
  AND sw.avg_prev_30d_count > 0
  AND sw.window_payment_sum >= 3.0 * sw.avg_prev_30d_amount
  AND sw.window_payment_count >= 3.0 * sw.avg_prev_30d_count
ORDER BY
    deviation_rank,
    sw.window_start,
    cg.customer_id;