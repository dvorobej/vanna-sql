WITH
payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        h.h03 || ' ' || h.h04 AS customer_name,
        c.c01 AS country_id,
        c.c02 AS country_name,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        p.p05 AS amount,
        p.p06 AS payment_ts,
        strftime('%Y-%m', p.p06) AS pay_month,
        date(p.p06) AS pay_day
    FROM pay AS p
    JOIN cus AS h ON h.h01 = p.p02
    JOIN adr AS a ON a.e01 = h.h06
    JOIN cty AS t ON t.d01 = a.e05
    JOIN cnt AS c ON c.c01 = t.d03
    JOIN stf AS s ON s.o01 = p.p03
),
monthly_client AS (
    SELECT
        customer_id,
        customer_name,
        country_id,
        country_name,
        pay_month,
        SUM(amount) AS monthly_amount,
        COUNT(*) AS payment_count
    FROM payment_base
    GROUP BY
        customer_id,
        customer_name,
        country_id,
        country_name,
        pay_month
),
monthly_with_history AS (
    SELECT
        mc.*,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY pay_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_monthly_amount,
        AVG(payment_count) OVER (
            PARTITION BY customer_id
            ORDER BY pay_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_payment_count
    FROM monthly_client AS mc
),
daily_client AS (
    SELECT
        customer_id,
        pay_month,
        pay_day,
        COUNT(*) AS daily_payment_count,
        COUNT(DISTINCT staff_id) AS daily_staff_count,
        COUNT(DISTINCT store_id) AS daily_store_count
    FROM payment_base
    GROUP BY
        customer_id,
        pay_month,
        pay_day
),
monthly_daily_share AS (
    SELECT
        customer_id,
        pay_month,
        1.0 * SUM(CASE WHEN daily_staff_count > 1 THEN daily_payment_count ELSE 0 END)
            / SUM(daily_payment_count) AS share_multi_staff_same_day,
        1.0 * SUM(CASE WHEN daily_store_count > 1 THEN daily_payment_count ELSE 0 END)
            / SUM(daily_payment_count) AS share_multi_store_same_day,
        1.0 * SUM(CASE WHEN daily_staff_count > 1 OR daily_store_count > 1 THEN daily_payment_count ELSE 0 END)
            / SUM(daily_payment_count) AS share_multi_staff_or_store_same_day
    FROM daily_client
    GROUP BY
        customer_id,
        pay_month
),
payment_windows AS (
    SELECT
        p1.customer_id,
        p1.pay_month,
        p1.payment_id,
        COUNT(p2.payment_id) AS payments_in_24h,
        COUNT(DISTINCT p2.staff_id) AS staff_count_in_24h
    FROM payment_base AS p1
    JOIN payment_base AS p2
        ON p2.customer_id = p1.customer_id
       AND julianday(p2.payment_ts) >= julianday(p1.payment_ts)
       AND julianday(p2.payment_ts) <= julianday(p1.payment_ts) + 1
    GROUP BY
        p1.customer_id,
        p1.pay_month,
        p1.payment_id
),
series_24h AS (
    SELECT
        customer_id,
        pay_month,
        MAX(CASE WHEN payments_in_24h >= 3 AND staff_count_in_24h >= 2 THEN 1 ELSE 0 END) AS has_multi_staff_24h_series,
        MAX(CASE WHEN payments_in_24h >= 3 AND staff_count_in_24h >= 2 THEN payments_in_24h ELSE 0 END) AS max_payments_in_24h_series
    FROM payment_windows
    GROUP BY
        customer_id,
        pay_month
),
country_ranked AS (
    SELECT
        mwh.*,
        AVG(monthly_amount) OVER (
            PARTITION BY country_id, pay_month
        ) AS country_avg_monthly_amount,
        RANK() OVER (
            PARTITION BY country_id, pay_month
            ORDER BY monthly_amount DESC
        ) AS country_month_amount_rank,
        COUNT(*) OVER (
            PARTITION BY country_id, pay_month
        ) AS country_month_customer_count
    FROM monthly_with_history AS mwh
)
SELECT
    cr.customer_id,
    cr.customer_name,
    cr.country_name,
    cr.pay_month,
    ROUND(cr.monthly_amount, 2) AS monthly_amount,
    cr.payment_count,
    ROUND(cr.prev_avg_monthly_amount, 2) AS prev_avg_monthly_amount,
    ROUND(cr.prev_avg_payment_count, 2) AS prev_avg_payment_count,
    ROUND(cr.monthly_amount / NULLIF(cr.prev_avg_monthly_amount, 0), 2) AS personal_amount_ratio,
    ROUND(cr.payment_count / NULLIF(cr.prev_avg_payment_count, 0), 2) AS personal_count_ratio,
    ROUND(cr.country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
    ROUND(cr.monthly_amount - cr.country_avg_monthly_amount, 2) AS country_amount_deviation,
    ROUND(cr.monthly_amount / NULLIF(cr.country_avg_monthly_amount, 0), 2) AS country_amount_ratio,
    ROUND(mds.share_multi_staff_same_day, 4) AS share_multi_staff_same_day,
    ROUND(mds.share_multi_store_same_day, 4) AS share_multi_store_same_day,
    ROUND(mds.share_multi_staff_or_store_same_day, 4) AS share_multi_staff_or_store_same_day,
    cr.country_month_amount_rank,
    cr.country_month_customer_count,
    COALESCE(s24.has_multi_staff_24h_series, 0) AS has_multi_staff_24h_series,
    COALESCE(s24.max_payments_in_24h_series, 0) AS max_payments_in_24h_series
FROM country_ranked AS cr
JOIN monthly_daily_share AS mds
    ON mds.customer_id = cr.customer_id
   AND mds.pay_month = cr.pay_month
LEFT JOIN series_24h AS s24
    ON s24.customer_id = cr.customer_id
   AND s24.pay_month = cr.pay_month
WHERE cr.prev_avg_monthly_amount IS NOT NULL
  AND cr.prev_avg_payment_count IS NOT NULL
  AND cr.monthly_amount >= 3 * cr.prev_avg_monthly_amount
  AND cr.payment_count >= 3 * cr.prev_avg_payment_count
  AND (
        cr.country_month_amount_rank <= ((cr.country_month_customer_count + 19) / 20)
        OR COALESCE(s24.has_multi_staff_24h_series, 0) = 1
      )
ORDER BY
    cr.country_name,
    cr.pay_month,
    cr.monthly_amount DESC,
    cr.customer_id;