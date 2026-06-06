WITH RECURSIVE
months(month_start) AS (
    SELECT date('2005-01-01')
    UNION ALL
    SELECT date(month_start, '+1 month')
    FROM months
    WHERE month_start < date('2005-12-01')
),
customer_base AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 AS first_name,
        cus.h04 AS last_name,
        adr.e05 AS city_id,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
payment_agg AS (
    SELECT
        pay.p02 AS customer_id,
        date(strftime('%Y-%m-01', pay.p06)) AS month_start,
        COUNT(*) AS payment_count,
        SUM(pay.p05) AS total_amount,
        AVG(pay.p05) AS avg_check,
        COUNT(DISTINCT pay.p03) AS distinct_staff_count,
        MAX(pay.p05) AS max_payment
    FROM pay
    WHERE pay.p06 >= '2005-01-01'
      AND pay.p06 < '2006-01-01'
    GROUP BY
        pay.p02,
        date(strftime('%Y-%m-01', pay.p06))
),
customer_month AS (
    SELECT
        cb.customer_id,
        cb.first_name,
        cb.last_name,
        cb.city_id,
        cb.city_name,
        cb.country_id,
        cb.country_name,
        m.month_start,
        COALESCE(pa.payment_count, 0) AS payment_count,
        COALESCE(pa.total_amount, 0.0) AS total_amount,
        pa.avg_check AS avg_check,
        COALESCE(pa.distinct_staff_count, 0) AS distinct_staff_count,
        pa.max_payment AS max_payment
    FROM customer_base AS cb
    CROSS JOIN months AS m
    LEFT JOIN payment_agg AS pa
        ON pa.customer_id = cb.customer_id
       AND pa.month_start = m.month_start
),
benchmarked AS (
    SELECT
        cm.*,
        AVG(cm.payment_count * 1.0) OVER (
            PARTITION BY cm.month_start, cm.city_id
        ) AS city_avg_payment_count,
        AVG(cm.total_amount) OVER (
            PARTITION BY cm.month_start, cm.city_id
        ) AS city_avg_total_amount,
        AVG(cm.avg_check) OVER (
            PARTITION BY cm.month_start, cm.city_id
        ) AS city_avg_check,
        AVG(cm.payment_count * 1.0) OVER (
            PARTITION BY cm.month_start, cm.country_id
        ) AS country_avg_payment_count,
        AVG(cm.total_amount) OVER (
            PARTITION BY cm.month_start, cm.country_id
        ) AS country_avg_total_amount,
        AVG(cm.avg_check) OVER (
            PARTITION BY cm.month_start, cm.country_id
        ) AS country_avg_check,
        COUNT(*) OVER (
            PARTITION BY cm.month_start, cm.country_id
        ) AS country_customer_count,
        ROW_NUMBER() OVER (
            PARTITION BY cm.month_start, cm.country_id
            ORDER BY cm.total_amount DESC, cm.payment_count DESC, cm.customer_id
        ) AS country_amount_position,
        LAG(cm.total_amount) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.month_start
        ) AS previous_month_amount
    FROM customer_month AS cm
)
SELECT
    strftime('%Y-%m', month_start) AS payment_month,
    customer_id,
    first_name,
    last_name,
    city_name,
    country_name,
    payment_count,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(avg_check, 2) AS avg_check,
    ROUND(city_avg_payment_count, 2) AS city_avg_payment_count,
    ROUND(city_avg_total_amount, 2) AS city_avg_total_amount,
    ROUND(city_avg_check, 2) AS city_avg_check,
    ROUND(country_avg_payment_count, 2) AS country_avg_payment_count,
    ROUND(country_avg_total_amount, 2) AS country_avg_total_amount,
    ROUND(country_avg_check, 2) AS country_avg_check,
    ROUND(previous_month_amount, 2) AS previous_month_amount,
    CASE
        WHEN previous_month_amount IS NULL OR previous_month_amount = 0 THEN NULL
        ELSE ROUND((total_amount - previous_month_amount) * 100.0 / previous_month_amount, 2)
    END AS growth_percent_to_previous_month,
    distinct_staff_count,
    ROUND(max_payment, 2) AS max_payment,
    country_amount_position,
    country_customer_count,
    CASE
        WHEN total_amount >= 3.0 * city_avg_total_amount THEN 1
        ELSE 0
    END AS is_3x_city_average,
    CASE
        WHEN country_amount_position <= CAST((country_customer_count + 19) / 20 AS INTEGER) THEN 1
        ELSE 0
    END AS is_top_5_percent_country
FROM benchmarked
WHERE total_amount > 0
  AND (
      total_amount >= 3.0 * city_avg_total_amount
      OR country_amount_position <= CAST((country_customer_count + 19) / 20 AS INTEGER)
  )
ORDER BY
    month_start,
    country_name,
    total_amount DESC,
    customer_id;