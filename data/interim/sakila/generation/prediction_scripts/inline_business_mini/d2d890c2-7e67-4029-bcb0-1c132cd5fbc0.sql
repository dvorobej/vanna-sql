WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        country.c01 AS country_id,
        country.c02 AS country_name,
        city.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS country
        ON country.c01 = city.d03
),
payment_detail AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        p.p03 AS staff_id,
        stf.o07 AS store_id,
        CAST(p.p05 AS REAL) AS amount
    FROM pay AS p
    JOIN stf AS stf
        ON stf.o01 = p.p03
),
daily_customer AS (
    SELECT
        customer_id,
        payment_day,
        COUNT(*) AS payment_count,
        SUM(amount) AS daily_sum,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT store_id) AS store_count
    FROM payment_detail
    GROUP BY customer_id, payment_day
),
daily_customer_hist AS (
    SELECT
        dc.*,
        AVG(daily_sum) OVER (
            PARTITION BY customer_id
            ORDER BY payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS prev30_avg_sum,
        AVG(payment_count) OVER (
            PARTITION BY customer_id
            ORDER BY payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS prev30_avg_count,
        COUNT(*) OVER (
            PARTITION BY customer_id
            ORDER BY payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS prev30_days_cnt
    FROM daily_customer AS dc
),
country_daily AS (
    SELECT
        cg.country_id,
        dc.payment_day,
        SUM(dc.daily_sum) AS country_daily_sum
    FROM daily_customer AS dc
    JOIN customer_geo AS cg
        ON cg.customer_id = dc.customer_id
    GROUP BY cg.country_id, dc.payment_day
),
country_daily_rank AS (
    SELECT
        country_id,
        payment_day,
        country_daily_sum,
        CUME_DIST() OVER (
            PARTITION BY country_id, strftime('%Y-%m', payment_day)
            ORDER BY country_daily_sum
        ) AS country_cume_dist
    FROM country_daily
),
scored AS (
    SELECT
        dch.customer_id,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        dch.payment_day,
        dch.payment_count,
        dch.daily_sum,
        dch.prev30_avg_sum,
        dch.staff_count,
        dch.store_count,
        cdr.country_cume_dist,
        (dch.daily_sum / NULLIF(dch.prev30_avg_sum, 0)) AS personal_ratio,
        (dch.daily_sum) AS country_level_amount
    FROM daily_customer_hist AS dch
    JOIN customer_geo AS cg
        ON cg.customer_id = dch.customer_id
    JOIN country_daily_rank AS cdr
        ON cdr.country_id = cg.country_id
       AND cdr.payment_day = dch.payment_day
    WHERE dch.prev30_days_cnt >= 30
      AND dch.prev30_avg_sum > 0
      AND dch.payment_count >= 3
      AND dch.daily_sum >= 3.0 * dch.prev30_avg_sum
      AND cdr.country_cume_dist >= 0.95
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    payment_day,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    ROUND(prev30_avg_sum, 2) AS prev30_avg_sum,
    ROUND(daily_sum - prev30_avg_sum, 2) AS deviation_from_personal_norm,
    staff_count,
    store_count,
    ROUND(personal_ratio, 2) AS personal_ratio,
    ROUND(
        RANK() OVER (
            PARTITION BY strftime('%Y-%m', payment_day)
            ORDER BY daily_sum DESC, personal_ratio DESC
        ),
        0
    ) AS suspicion_rank
FROM scored
ORDER BY
    payment_day,
    suspicion_rank,
    customer_id;