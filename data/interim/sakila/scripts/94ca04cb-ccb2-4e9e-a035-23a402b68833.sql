WITH RECURSIVE
bounds AS (
    SELECT
        date(MIN(p06), 'start of month') AS min_month,
        date(MAX(p06), 'start of month') AS max_month
    FROM pay
    WHERE p04 IS NOT NULL
),
months(month_start) AS (
    SELECT min_month
    FROM bounds
    WHERE min_month IS NOT NULL

    UNION ALL

    SELECT date(month_start, '+1 month')
    FROM months
    CROSS JOIN bounds
    WHERE month_start < max_month
),
customer_base AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 AS first_name,
        cus.h04 AS last_name,
        cus.h02 AS store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
payment_agg AS (
    SELECT
        pay.p02 AS customer_id,
        date(pay.p06, 'start of month') AS month_start,
        SUM(pay.p05) AS month_payment_amount,
        COUNT(*) AS month_payment_count,
        COUNT(DISTINCT pay.p03) AS distinct_staff_count
    FROM pay
    WHERE pay.p04 IS NOT NULL
    GROUP BY
        pay.p02,
        date(pay.p06, 'start of month')
),
filled_months AS (
    SELECT
        cb.customer_id,
        cb.first_name,
        cb.last_name,
        cb.store_id,
        cb.country_id,
        cb.country_name,
        cb.city_name,
        m.month_start,
        COALESCE(pa.month_payment_amount, 0) AS month_payment_amount,
        COALESCE(pa.month_payment_count, 0) AS month_payment_count,
        COALESCE(pa.distinct_staff_count, 0) AS distinct_staff_count
    FROM customer_base AS cb
    CROSS JOIN months AS m
    LEFT JOIN payment_agg AS pa
        ON pa.customer_id = cb.customer_id
       AND pa.month_start = m.month_start
),
monthly_analytics AS (
    SELECT
        fm.*,
        AVG(fm.month_payment_amount) OVER (
            PARTITION BY fm.customer_id
            ORDER BY fm.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_amount_prev_3_months,
        COUNT(*) OVER (
            PARTITION BY fm.customer_id
            ORDER BY fm.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_count,
        RANK() OVER (
            PARTITION BY fm.country_id, fm.month_start
            ORDER BY fm.month_payment_amount DESC
        ) AS country_month_amount_rank
    FROM filled_months AS fm
),
store_month_counts AS (
    SELECT
        store_id,
        month_start,
        month_payment_count,
        ROW_NUMBER() OVER (
            PARTITION BY store_id, month_start
            ORDER BY month_payment_count
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY store_id, month_start
        ) AS cnt
    FROM filled_months
),
store_month_median AS (
    SELECT
        store_id,
        month_start,
        AVG(month_payment_count * 1.0) AS median_payment_count
    FROM store_month_counts
    WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY
        store_id,
        month_start
)
SELECT
    ma.customer_id,
    ma.first_name,
    ma.last_name,
    ma.country_name,
    ma.city_name,
    ma.store_id,
    strftime('%Y-%m', ma.month_start) AS anomaly_month,
    ROUND(ma.month_payment_amount, 2) AS month_payment_amount,
    ma.month_payment_count,
    ROUND(ma.avg_amount_prev_3_months, 2) AS avg_amount_prev_3_months,
    ROUND(
        CASE
            WHEN ma.month_payment_count = 0 THEN 0
            ELSE ma.distinct_staff_count * 1.0 / ma.month_payment_count
        END,
        4
    ) AS staff_diversity_share,
    ma.country_month_amount_rank
FROM monthly_analytics AS ma
JOIN store_month_median AS smm
    ON smm.store_id = ma.store_id
   AND smm.month_start = ma.month_start
WHERE ma.prev_3_months_count = 3
  AND ma.avg_amount_prev_3_months > 0
  AND ma.month_payment_amount > ma.avg_amount_prev_3_months * 2
  AND ma.month_payment_count > smm.median_payment_count
ORDER BY
    ma.month_start,
    ma.country_name,
    ma.country_month_amount_rank,
    ma.customer_id;