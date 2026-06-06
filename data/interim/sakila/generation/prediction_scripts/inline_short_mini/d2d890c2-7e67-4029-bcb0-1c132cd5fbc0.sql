WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(*) AS daily_payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM pay AS p
    JOIN stf AS stf
        ON stf.o01 = p.p03
    GROUP BY
        p.p02,
        DATE(p.p06)
),
customer_history AS (
    SELECT
        dp.*,
        AVG(dp.daily_amount) OVER (
            PARTITION BY dp.customer_id
            ORDER BY dp.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_30d,
        AVG(dp.daily_payment_count) OVER (
            PARTITION BY dp.customer_id
            ORDER BY dp.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS personal_count_avg_30d
    FROM daily_payments AS dp
),
country_daily AS (
    SELECT
        cty.d03 AS country_id,
        DATE(p.p06) AS payment_day,
        SUM(CAST(p.p05 AS REAL)) AS country_daily_amount
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    GROUP BY
        cty.d03,
        DATE(p.p06)
),
country_history AS (
    SELECT
        cd.*,
        AVG(cd.country_daily_amount) OVER (
            PARTITION BY cd.country_id
            ORDER BY cd.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS country_avg_30d
    FROM country_daily AS cd
),
scored AS (
    SELECT
        ch.customer_id,
        cus.h03 AS first_name,
        cus.h04 AS last_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        ch.payment_day,
        ch.daily_amount,
        ch.daily_payment_count,
        ch.staff_count,
        ch.store_count,
        ch.personal_avg_30d,
        ch.personal_count_avg_30d,
        country_history.country_avg_30d,
        CASE
            WHEN ch.personal_avg_30d IS NULL OR ch.personal_avg_30d = 0 THEN NULL
            ELSE ch.daily_amount / ch.personal_avg_30d
        END AS personal_amount_ratio,
        CASE
            WHEN country_history.country_avg_30d IS NULL OR country_history.country_avg_30d = 0 THEN NULL
            ELSE ch.daily_amount / country_history.country_avg_30d
        END AS country_amount_ratio,
        CASE
            WHEN ch.staff_count > 1 OR ch.store_count > 1 THEN 1
            ELSE 0
        END AS multi_staff_store_flag
    FROM customer_history AS ch
    JOIN cus AS cus
        ON cus.h01 = ch.customer_id
    JOIN adr AS a
        ON a.e01 = cus.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
    LEFT JOIN country_history AS country_history
        ON country_history.payment_day = ch.payment_day
       AND country_history.country_id = cty.d03
)
SELECT
    customer_id,
    first_name,
    last_name,
    country,
    city,
    payment_day,
    ROUND(daily_amount, 2) AS daily_amount,
    daily_payment_count,
    ROUND(personal_avg_30d, 2) AS personal_avg_30d,
    ROUND(country_avg_30d, 2) AS country_avg_30d,
    ROUND(personal_amount_ratio, 2) AS personal_amount_ratio,
    ROUND(country_amount_ratio, 2) AS country_amount_ratio,
    staff_count,
    store_count,
    multi_staff_store_flag,
    RANK() OVER (
        ORDER BY
            COALESCE(personal_amount_ratio, 0) DESC,
            COALESCE(country_amount_ratio, 0) DESC,
            daily_amount DESC
    ) AS suspicion_rank
FROM scored
WHERE daily_payment_count >= 3
  AND personal_avg_30d IS NOT NULL
  AND personal_avg_30d > 0
  AND country_avg_30d IS NOT NULL
  AND country_avg_30d > 0
  AND daily_amount >= personal_avg_30d * 3
  AND daily_amount >= country_avg_30d * 3
  AND (staff_count > 1 OR store_count > 1)
ORDER BY
    suspicion_rank,
    payment_day,
    daily_amount DESC,
    customer_id;