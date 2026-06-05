WITH RECURSIVE
params(amount_multiplier, count_multiplier) AS (
    SELECT 2.0, 2.0
),
payment_bounds(min_day, max_day) AS (
    SELECT date(MIN(p06)), date(MAX(p06))
    FROM pay
),
calendar(payment_day) AS (
    SELECT min_day
    FROM payment_bounds
    WHERE min_day IS NOT NULL

    UNION ALL

    SELECT date(calendar.payment_day, '+1 day')
    FROM calendar
    CROSS JOIN payment_bounds
    WHERE calendar.payment_day < payment_bounds.max_day
),
customer_dim AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cus.h02 AS home_store_id,
        cty.d01 AS city_id,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_payments AS (
    SELECT
        pay.p02 AS customer_id,
        date(pay.p06) AS payment_day,
        SUM(CAST(pay.p05 AS REAL)) AS daily_payment_amount,
        COUNT(*) AS daily_payment_count,
        COUNT(DISTINCT pay.p04) AS related_rental_count,
        COUNT(DISTINCT pay.p03) AS involved_staff_count,
        COUNT(DISTINCT stf.o07) AS involved_store_count,
        group_concat(DISTINCT CAST(stf.o07 AS TEXT)) AS involved_store_ids,
        group_concat(DISTINCT CAST(stf.o01 AS TEXT) || ':' || stf.o02 || ' ' || stf.o03) AS involved_staff
    FROM pay
    JOIN stf ON stf.o01 = pay.p03
    GROUP BY
        pay.p02,
        date(pay.p06)
),
customer_calendar AS (
    SELECT
        cd.customer_id,
        cd.customer_name,
        cd.home_store_id,
        cd.city_id,
        cd.city_name,
        cd.country_id,
        cd.country_name,
        cal.payment_day,
        COALESCE(dp.daily_payment_amount, 0.0) AS daily_payment_amount,
        COALESCE(dp.daily_payment_count, 0) AS daily_payment_count,
        COALESCE(dp.related_rental_count, 0) AS related_rental_count,
        COALESCE(dp.involved_staff_count, 0) AS involved_staff_count,
        COALESCE(dp.involved_store_count, 0) AS involved_store_count,
        dp.involved_store_ids,
        dp.involved_staff
    FROM customer_dim AS cd
    CROSS JOIN calendar AS cal
    LEFT JOIN daily_payments AS dp
        ON dp.customer_id = cd.customer_id
       AND dp.payment_day = cal.payment_day
),
rolling_baseline AS (
    SELECT
        customer_calendar.*,
        COUNT(*) OVER (
            PARTITION BY customer_id
            ORDER BY payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS baseline_days,
        AVG(daily_payment_amount) OVER (
            PARTITION BY customer_id
            ORDER BY payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS rolling_30d_avg_payment_amount,
        AVG(daily_payment_count) OVER (
            PARTITION BY customer_id
            ORDER BY payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS rolling_30d_avg_payment_count
    FROM customer_calendar
),
country_ranked AS (
    SELECT
        rolling_baseline.*,
        RANK() OVER (
            PARTITION BY payment_day, country_id
            ORDER BY daily_payment_amount DESC
        ) AS country_daily_amount_rank,
        COUNT(*) OVER (
            PARTITION BY payment_day, country_id
        ) AS country_customer_count
    FROM rolling_baseline
)
SELECT
    payment_day,
    customer_id,
    customer_name,
    home_store_id,
    city_name,
    country_name,
    daily_payment_amount,
    daily_payment_count,
    ROUND(rolling_30d_avg_payment_amount, 2) AS rolling_30d_avg_payment_amount,
    ROUND(rolling_30d_avg_payment_count, 2) AS rolling_30d_avg_payment_count,
    CASE
        WHEN rolling_30d_avg_payment_amount = 0 THEN NULL
        ELSE ROUND(daily_payment_amount / rolling_30d_avg_payment_amount, 2)
    END AS amount_to_30d_avg_ratio,
    CASE
        WHEN rolling_30d_avg_payment_count = 0 THEN NULL
        ELSE ROUND(daily_payment_count / rolling_30d_avg_payment_count, 2)
    END AS count_to_30d_avg_ratio,
    related_rental_count,
    involved_store_ids,
    involved_staff,
    involved_staff_count,
    involved_store_count,
    country_daily_amount_rank,
    country_customer_count,
    ((country_customer_count + 19) / 20) AS country_top_5_percent_cutoff,
    CASE
        WHEN involved_staff_count > 1 OR involved_store_count > 1 THEN 1
        ELSE 0
    END AS multiple_staff_or_store_flag
FROM country_ranked
CROSS JOIN params
WHERE baseline_days = 30
  AND daily_payment_count > 0
  AND daily_payment_amount > rolling_30d_avg_payment_amount * params.amount_multiplier
  AND daily_payment_count > rolling_30d_avg_payment_count * params.count_multiplier
  AND country_daily_amount_rank <= ((country_customer_count + 19) / 20)
ORDER BY
    payment_day,
    country_name,
    country_daily_amount_rank,
    daily_payment_amount DESC,
    customer_id;