WITH RECURSIVE
date_bounds AS (
    SELECT
        date(MIN(p06)) AS min_date,
        date(MAX(p06)) AS max_date
    FROM pay
),
calendar_days(day_date) AS (
    SELECT min_date
    FROM date_bounds
    WHERE min_date IS NOT NULL

    UNION ALL

    SELECT date(day_date, '+1 day')
    FROM calendar_days, date_bounds
    WHERE day_date < max_date
),
customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
payment_detail AS (
    SELECT
        pay.p01 AS payment_id,
        pay.p02 AS customer_id,
        date(pay.p06) AS payment_date,
        CAST(pay.p05 AS REAL) AS amount,
        pay.p03 AS staff_id,
        stf.o07 AS store_id
    FROM pay
    JOIN stf ON stf.o01 = pay.p03
),
daily_payments AS (
    SELECT
        customer_id,
        payment_date,
        COUNT(*) AS daily_payment_count,
        SUM(amount) AS daily_amount
    FROM payment_detail
    GROUP BY
        customer_id,
        payment_date
),
customer_calendar AS (
    SELECT
        cg.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        cd.day_date
    FROM customer_geo AS cg
    CROSS JOIN calendar_days AS cd
),
daily_series AS (
    SELECT
        cc.customer_id,
        cc.customer_name,
        cc.city_name,
        cc.country_id,
        cc.country_name,
        cc.day_date,
        COALESCE(dp.daily_payment_count, 0) AS daily_payment_count,
        COALESCE(dp.daily_amount, 0.0) AS daily_amount
    FROM customer_calendar AS cc
    LEFT JOIN daily_payments AS dp
        ON dp.customer_id = cc.customer_id
       AND dp.payment_date = cc.day_date
),
rolling_windows AS (
    SELECT
        ds.customer_id,
        ds.customer_name,
        ds.city_name,
        ds.country_id,
        ds.country_name,
        date(ds.day_date, '-6 days') AS window_start,
        ds.day_date AS window_end,
        strftime('%Y-%m', ds.day_date) AS anomaly_month,
        SUM(ds.daily_payment_count) OVER (
            PARTITION BY ds.customer_id
            ORDER BY ds.day_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS window_payment_count,
        SUM(ds.daily_amount) OVER (
            PARTITION BY ds.customer_id
            ORDER BY ds.day_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS window_amount,
        COUNT(*) OVER (
            PARTITION BY ds.customer_id
            ORDER BY ds.day_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS prev30_day_count,
        SUM(ds.daily_payment_count) OVER (
            PARTITION BY ds.customer_id
            ORDER BY ds.day_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) * 7.0 / 30.0 AS prev30_avg_7day_payment_count,
        SUM(ds.daily_amount) OVER (
            PARTITION BY ds.customer_id
            ORDER BY ds.day_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) * 7.0 / 30.0 AS prev30_avg_7day_amount
    FROM daily_series AS ds
),
window_staff_store AS (
    SELECT
        rw.customer_id,
        rw.customer_name,
        rw.city_name,
        rw.country_id,
        rw.country_name,
        rw.window_start,
        rw.window_end,
        rw.anomaly_month,
        rw.window_payment_count,
        rw.window_amount,
        rw.prev30_avg_7day_payment_count,
        rw.prev30_avg_7day_amount,
        COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pd.store_id) AS distinct_store_count
    FROM rolling_windows AS rw
    JOIN payment_detail AS pd
        ON pd.customer_id = rw.customer_id
       AND pd.payment_date BETWEEN rw.window_start AND rw.window_end
    WHERE rw.prev30_day_count = 30
    GROUP BY
        rw.customer_id,
        rw.customer_name,
        rw.city_name,
        rw.country_id,
        rw.country_name,
        rw.window_start,
        rw.window_end,
        rw.anomaly_month,
        rw.window_payment_count,
        rw.window_amount,
        rw.prev30_avg_7day_payment_count,
        rw.prev30_avg_7day_amount
),
suspicious_windows AS (
    SELECT
        *,
        window_amount - prev30_avg_7day_amount AS amount_excess,
        window_payment_count - prev30_avg_7day_payment_count AS count_excess,
        window_amount / NULLIF(prev30_avg_7day_amount, 0) AS amount_ratio_to_history,
        window_payment_count / NULLIF(prev30_avg_7day_payment_count, 0) AS count_ratio_to_history
    FROM window_staff_store
    WHERE prev30_avg_7day_amount > 0
      AND prev30_avg_7day_payment_count > 0
      AND window_amount >= 3.0 * prev30_avg_7day_amount
      AND window_payment_count >= 3.0 * prev30_avg_7day_payment_count
      AND (distinct_staff_count > 1 OR distinct_store_count > 1)
),
best_customer_month_window AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY anomaly_month, customer_id
            ORDER BY amount_excess DESC, window_amount DESC, window_payment_count DESC
        ) AS rn
    FROM suspicious_windows
)
SELECT
    anomaly_month,
    customer_id,
    customer_name,
    country_name,
    city_name,
    window_start,
    window_end,
    window_payment_count,
    ROUND(window_amount, 2) AS window_amount,
    ROUND(prev30_avg_7day_payment_count, 2) AS prev30_avg_7day_payment_count,
    ROUND(prev30_avg_7day_amount, 2) AS prev30_avg_7day_amount,
    ROUND(count_excess, 2) AS count_excess,
    ROUND(amount_excess, 2) AS amount_excess,
    ROUND(count_ratio_to_history, 2) AS count_ratio_to_history,
    ROUND(amount_ratio_to_history, 2) AS amount_ratio_to_history,
    distinct_staff_count,
    distinct_store_count,
    RANK() OVER (
        PARTITION BY anomaly_month
        ORDER BY amount_excess DESC, amount_ratio_to_history DESC, window_amount DESC
    ) AS monthly_risk_rank
FROM best_customer_month_window
WHERE rn = 1
ORDER BY
    anomaly_month,
    monthly_risk_rank,
    customer_id;