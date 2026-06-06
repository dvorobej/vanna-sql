WITH RECURSIVE
params(amount_multiplier, count_multiplier) AS (
    SELECT 3.0, 3.0
),
payment_bounds AS (
    SELECT
        date(MIN(p06)) AS min_day,
        date(MAX(p06)) AS max_day
    FROM pay
),
calendar(payment_day) AS (
    SELECT min_day
    FROM payment_bounds
    WHERE min_day IS NOT NULL

    UNION ALL

    SELECT date(payment_day, '+1 day')
    FROM calendar
    CROSS JOIN payment_bounds
    WHERE payment_day < max_day
),
customer_dim AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
payment_detail AS (
    SELECT
        pay.p01 AS payment_id,
        pay.p02 AS customer_id,
        pay.p03 AS staff_id,
        stf.o02 || ' ' || stf.o03 AS staff_name,
        stf.o07 AS staff_store_id,
        date(pay.p06) AS payment_day,
        pay.p06 AS payment_ts,
        CAST(pay.p05 AS REAL) AS amount,
        pay.p04 AS rental_id,
        ren.q02 AS rental_date,
        ren.q05 AS return_date,
        flm.i07 AS rental_duration_days
    FROM pay
    JOIN stf ON stf.o01 = pay.p03
    LEFT JOIN ren ON ren.q01 = pay.p04
    LEFT JOIN inv ON inv.n01 = ren.q03
    LEFT JOIN flm ON flm.i01 = inv.n02
),
daily_payments AS (
    SELECT
        customer_id,
        payment_day,
        COUNT(*) AS daily_payment_count,
        SUM(amount) AS daily_payment_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT staff_store_id) AS distinct_store_count,
        COUNT(DISTINCT rental_id) AS related_rental_count,
        COUNT(DISTINCT CASE
            WHEN rental_id IS NOT NULL
             AND return_date IS NOT NULL
             AND datetime(return_date) > datetime(rental_date, '+' || rental_duration_days || ' days')
            THEN rental_id
        END) AS overdue_rental_count
    FROM payment_detail
    GROUP BY
        customer_id,
        payment_day
),
last_payment AS (
    SELECT
        customer_id,
        payment_day,
        payment_id AS last_payment_id,
        payment_ts AS last_payment_ts,
        staff_id AS last_staff_id,
        staff_name AS last_staff_name,
        staff_store_id AS last_store_id
    FROM (
        SELECT
            payment_detail.*,
            ROW_NUMBER() OVER (
                PARTITION BY customer_id, payment_day
                ORDER BY payment_ts DESC, payment_id DESC
            ) AS rn
        FROM payment_detail
    )
    WHERE rn = 1
),
customer_calendar AS (
    SELECT
        cd.customer_id,
        cd.customer_name,
        cd.country_id,
        cd.country_name,
        cd.city_name,
        cal.payment_day,
        COALESCE(dp.daily_payment_count, 0) AS daily_payment_count,
        COALESCE(dp.daily_payment_amount, 0.0) AS daily_payment_amount,
        COALESCE(dp.distinct_staff_count, 0) AS distinct_staff_count,
        COALESCE(dp.distinct_store_count, 0) AS distinct_store_count,
        COALESCE(dp.related_rental_count, 0) AS related_rental_count,
        COALESCE(dp.overdue_rental_count, 0) AS overdue_rental_count
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
        ) AS avg_amount_prev_30d,
        AVG(daily_payment_count * 1.0) OVER (
            PARTITION BY customer_id
            ORDER BY payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_count_prev_30d
    FROM customer_calendar
),
country_ranked AS (
    SELECT
        rb.*,
        RANK() OVER (
            PARTITION BY payment_day, country_id
            ORDER BY daily_payment_amount DESC
        ) AS country_daily_amount_rank
    FROM rolling_baseline AS rb
),
suspicious AS (
    SELECT
        cr.*,
        cr.daily_payment_amount / NULLIF(cr.avg_amount_prev_30d, 0) AS amount_to_avg_ratio,
        cr.daily_payment_count / NULLIF(cr.avg_count_prev_30d, 0) AS count_to_avg_ratio,
        cr.daily_payment_amount - cr.avg_amount_prev_30d AS amount_deviation
    FROM country_ranked AS cr
    CROSS JOIN params
    WHERE cr.baseline_days = 30
      AND cr.daily_payment_count > 0
      AND cr.avg_amount_prev_30d > 0
      AND cr.avg_count_prev_30d > 0
      AND cr.daily_payment_amount >= cr.avg_amount_prev_30d * params.amount_multiplier
      AND cr.daily_payment_count >= cr.avg_count_prev_30d * params.count_multiplier
)
SELECT
    RANK() OVER (
        ORDER BY
            suspicious.amount_deviation DESC,
            suspicious.amount_to_avg_ratio DESC,
            suspicious.daily_payment_amount DESC
    ) AS anomaly_rank,
    suspicious.customer_id,
    suspicious.customer_name,
    suspicious.country_name,
    suspicious.city_name,
    suspicious.payment_day,
    lp.last_store_id,
    lp.last_staff_id,
    lp.last_staff_name,
    suspicious.daily_payment_count,
    ROUND(suspicious.daily_payment_amount, 2) AS daily_payment_amount,
    ROUND(suspicious.avg_amount_prev_30d, 2) AS avg_amount_prev_30d,
    ROUND(suspicious.avg_count_prev_30d, 2) AS avg_count_prev_30d,
    ROUND(suspicious.amount_deviation, 2) AS amount_deviation,
    ROUND(suspicious.amount_to_avg_ratio, 2) AS amount_to_avg_ratio,
    ROUND(suspicious.count_to_avg_ratio, 2) AS count_to_avg_ratio,
    suspicious.distinct_staff_count,
    suspicious.distinct_store_count,
    suspicious.related_rental_count,
    ROUND(
        suspicious.overdue_rental_count * 1.0 / NULLIF(suspicious.related_rental_count, 0),
        4
    ) AS overdue_return_share,
    suspicious.country_daily_amount_rank
FROM suspicious
JOIN last_payment AS lp
    ON lp.customer_id = suspicious.customer_id
   AND lp.payment_day = suspicious.payment_day
ORDER BY
    anomaly_rank,
    suspicious.payment_day,
    suspicious.customer_id;