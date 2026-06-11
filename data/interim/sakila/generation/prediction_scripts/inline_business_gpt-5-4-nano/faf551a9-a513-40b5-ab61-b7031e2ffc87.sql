WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        ci.d02 AS city_name,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        c.h02 AS store_id,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    GROUP BY
        p.p02,
        date(p.p06),
        c.h02
),
daily_with_history AS (
    SELECT
        dp.*,
        (SELECT AVG(dp2.day_amount)
         FROM daily_payments AS dp2
         WHERE dp2.customer_id = dp.customer_id
           AND dp2.payment_day >= date(dp.payment_day, '-30 days')
           AND dp2.payment_day < dp.payment_day
        ) AS avg_prev30_day_amount,
        (SELECT AVG(dp2.payment_count)
         FROM daily_payments AS dp2
         WHERE dp2.customer_id = dp.customer_id
           AND dp2.payment_day >= date(dp.payment_day, '-30 days')
           AND dp2.payment_day < dp.payment_day
        ) AS avg_prev30_day_count
    FROM daily_payments AS dp
),
country_day_exception AS (
    SELECT
        dwh.*,
        DENSE_RANK() OVER (
            PARTITION BY dwh.country_id, dwh.payment_day
            ORDER BY dwh.day_amount DESC
        ) AS country_day_amount_rank,
        COUNT(*) OVER (
            PARTITION BY dwh.country_id, dwh.payment_day
        ) AS country_day_customer_count
    FROM (
        SELECT
            dwh.*,
            cg.country_name AS country_id
        FROM daily_with_history AS dwh
        JOIN customer_geo AS cg
          ON cg.customer_id = dwh.customer_id
    ) AS dwh
),
scored AS (
    SELECT
        cde.customer_id,
        cg.customer_name,
        cg.country_name AS country,
        cg.city_name AS city,
        cde.store_id AS store_id,
        date(cde.payment_day) AS spike_date,
        cde.payment_count,
        ROUND(cde.day_amount, 2) AS day_amount,
        ROUND(cde.avg_prev30_day_amount, 2) AS avg_prev30_day_amount,
        ROUND(cde.day_amount - cde.avg_prev30_day_amount, 2) AS deviation_from_avg,
        cde.country_day_amount_rank,
        cde.country_day_customer_count
    FROM country_day_exception AS cde
    JOIN customer_geo AS cg ON cg.customer_id = cde.customer_id
)
SELECT
    spike_date,
    customer_name,
    country,
    city,
    store_id,
    payment_count,
    day_amount,
    avg_prev30_day_amount,
    deviation_from_avg,
    country_day_amount_rank AS spike_rank_within_country_day
FROM scored
WHERE avg_prev30_day_amount IS NOT NULL
  AND avg_prev30_day_amount > 0
  AND day_amount >= 3.0 * avg_prev30_day_amount
  AND country_day_amount_rank = 1
ORDER BY
    spike_date,
    country,
    store_id,
    spike_rank_within_country_day,
    customer_name;