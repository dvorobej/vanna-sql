WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        DATE(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        stf.o07 AS store_id
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS stf
        ON stf.o01 = p.p03
),
customer_days AS (
    SELECT
        customer_id,
        customer_name,
        country_id,
        country_name,
        city_name,
        payment_day,
        SUM(amount) AS day_amount,
        COUNT(*) AS day_payment_count,
        COUNT(DISTINCT staff_id) AS day_staff_count,
        COUNT(DISTINCT store_id) AS day_store_count
    FROM payment_base
    GROUP BY
        customer_id, customer_name, country_id, country_name, city_name, payment_day
),
window_metrics AS (
    SELECT
        cd.customer_id,
        cd.customer_name,
        cd.country_id,
        cd.country_name,
        cd.city_name,
        cd.payment_day AS window_start,
        DATE(cd.payment_day, '+6 day') AS window_end,
        SUM(CASE
                WHEN pb.payment_day BETWEEN cd.payment_day AND DATE(cd.payment_day, '+6 day')
                THEN pb.amount ELSE 0
            END) AS window_amount,
        COUNT(CASE
                WHEN pb.payment_day BETWEEN cd.payment_day AND DATE(cd.payment_day, '+6 day')
                THEN pb.payment_id END) AS window_payment_count,
        COUNT(DISTINCT CASE
                WHEN pb.payment_day BETWEEN cd.payment_day AND DATE(cd.payment_day, '+6 day')
                THEN pb.staff_id END) AS window_staff_count,
        COUNT(DISTINCT CASE
                WHEN pb.payment_day BETWEEN cd.payment_day AND DATE(cd.payment_day, '+6 day')
                THEN pb.store_id END) AS window_store_count,
        AVG(CASE
                WHEN pb.payment_day BETWEEN DATE(cd.payment_day, '-30 day') AND DATE(cd.payment_day, '-1 day')
                THEN pb.amount END) AS prev30_avg_payment_amount,
        COUNT(CASE
                WHEN pb.payment_day BETWEEN DATE(cd.payment_day, '-30 day') AND DATE(cd.payment_day, '-1 day')
                THEN pb.payment_id END) AS prev30_payment_count
    FROM customer_days AS cd
    JOIN payment_base AS pb
      ON pb.customer_id = cd.customer_id
     AND pb.payment_day BETWEEN DATE(cd.payment_day, '-30 day') AND DATE(cd.payment_day, '+6 day')
    GROUP BY
        cd.customer_id,
        cd.customer_name,
        cd.country_id,
        cd.country_name,
        cd.city_name,
        cd.payment_day
),
country_percentiles AS (
    SELECT
        country_id,
        payment_day,
        PERCENT_RANK() OVER (
            PARTITION BY country_id, payment_day
            ORDER BY day_amount
        ) AS country_day_amount_percent_rank,
        day_amount
    FROM customer_days
),
scored AS (
    SELECT
        wm.*,
        cp.country_day_amount_percent_rank,
        CASE
            WHEN wm.prev30_avg_payment_amount IS NULL OR wm.prev30_avg_payment_amount = 0 THEN NULL
            ELSE wm.window_amount / wm.prev30_avg_payment_amount
        END AS amount_to_prev30_ratio,
        CASE
            WHEN wm.prev30_payment_count = 0 THEN NULL
            ELSE wm.window_payment_count * 1.0 / wm.prev30_payment_count
        END AS count_to_prev30_ratio,
        ROW_NUMBER() OVER (
            PARTITION BY wm.country_id, wm.window_start
            ORDER BY
                (wm.window_amount / NULLIF(wm.prev30_avg_payment_amount, 0)) DESC,
                wm.window_amount DESC,
                wm.window_payment_count DESC
        ) AS suspicion_rank
    FROM window_metrics AS wm
    LEFT JOIN (
        SELECT
            country_id,
            payment_day,
            MAX(country_day_amount_percent_rank) AS country_day_amount_percent_rank
        FROM country_percentiles
        GROUP BY country_id, payment_day
    ) AS cp
      ON cp.country_id = wm.country_id
     AND cp.payment_day = wm.window_start
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    window_start,
    window_end,
    ROUND(window_amount, 2) AS window_amount,
    window_payment_count,
    window_staff_count,
    window_store_count,
    ROUND(prev30_avg_payment_amount, 2) AS prev30_avg_payment_amount,
    ROUND(amount_to_prev30_ratio, 2) AS amount_to_prev30_ratio,
    ROUND(count_to_prev30_ratio, 2) AS count_to_prev30_ratio,
    country_day_amount_percent_rank,
    suspicion_rank
FROM scored
WHERE prev30_avg_payment_amount IS NOT NULL
  AND prev30_avg_payment_amount > 0
  AND window_amount >= 3.0 * prev30_avg_payment_amount
  AND country_day_amount_percent_rank >= 0.95
ORDER BY
    suspicion_rank,
    window_amount DESC,
    customer_id;