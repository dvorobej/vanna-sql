WITH RECURSIVE
months AS (
    SELECT date('2005-01-01') AS month_start
    UNION ALL
    SELECT date(month_start, '+1 month')
    FROM months
    WHERE month_start < date('2005-12-01')
),
customer_location AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d01 AS city_id,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    WHERE c.h07 IN ('1', 'Y')
),
monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(strftime('%Y-%m-01', p.p06)) AS month_start,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
        p.p02,
        date(strftime('%Y-%m-01', p.p06))
),
customer_months AS (
    SELECT
        cl.customer_id,
        cl.customer_name,
        cl.country_id,
        cl.country_name,
        cl.city_id,
        cl.city_name,
        m.month_start,
        COALESCE(mp.payment_count, 0) AS payment_count,
        COALESCE(mp.monthly_amount, 0.0) AS monthly_amount,
        COALESCE(mp.staff_count, 0) AS staff_count,
        COALESCE(mp.store_count, 0) AS store_count
    FROM customer_location AS cl
    CROSS JOIN months AS m
    LEFT JOIN monthly_payments AS mp
      ON mp.customer_id = cl.customer_id
     AND mp.month_start = m.month_start
),
history_calc AS (
    SELECT
        cm.*,
        AVG(cm.monthly_amount) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_monthly_amount,
        COUNT(*) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_month_count
    FROM customer_months AS cm
),
country_month_median_payments AS (
    SELECT
        country_id,
        month_start,
        payment_count,
        PERCENT_RANK() OVER (
            PARTITION BY country_id, month_start
            ORDER BY payment_count
        ) AS pr
    FROM customer_months
),
country_month_median AS (
    SELECT
        country_id,
        month_start,
        MAX(payment_count) AS median_payment_count
    FROM country_month_median_payments
    WHERE pr <= 0.5
    GROUP BY country_id, month_start
),
ranked AS (
    SELECT
        hc.*,
        cmm.median_payment_count,
        RANK() OVER (
            PARTITION BY hc.country_id, hc.month_start
            ORDER BY hc.monthly_amount DESC
        ) AS country_amount_rank
    FROM history_calc AS hc
    JOIN country_month_median AS cmm
      ON cmm.country_id = hc.country_id
     AND cmm.month_start = hc.month_start
)
SELECT
    customer_name,
    country_name,
    city_name,
    strftime('%Y-%m', month_start) AS month,
    payment_count,
    ROUND(monthly_amount, 2) AS monthly_amount,
    ROUND(prev_avg_monthly_amount, 2) AS prev_avg_monthly_amount,
    ROUND(monthly_amount - prev_avg_monthly_amount, 2) AS deviation_from_prev_avg,
    staff_count,
    store_count,
    country_amount_rank
FROM ranked
WHERE prev_month_count >= 1
  AND monthly_amount >= 3.0 * prev_avg_monthly_amount
  AND payment_count > median_payment_count
  AND (staff_count > 1 OR store_count > 1)
ORDER BY
    country_name,
    month,
    country_amount_rank,
    monthly_amount DESC,
    customer_name;