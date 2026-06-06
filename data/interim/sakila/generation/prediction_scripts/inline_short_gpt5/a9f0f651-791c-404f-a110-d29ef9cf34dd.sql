WITH monthly_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        date(strftime('%Y-%m-01', p.p06)) AS month_start,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM cus AS c
    JOIN pay AS p
        ON p.p02 = c.h01
    JOIN stf
        ON stf.o01 = p.p03
    JOIN adr
        ON adr.e01 = c.h06
    JOIN cty
        ON cty.d01 = adr.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    WHERE c.h07 IN ('Y', '1')
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        cnt.c01,
        cnt.c02,
        cty.d02,
        date(strftime('%Y-%m-01', p.p06))
),
with_history AS (
    SELECT
        mp.*,
        AVG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_avg_monthly_amount,
        COUNT(*) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_month_count
    FROM monthly_payments AS mp
),
payments_2005 AS (
    SELECT *
    FROM with_history
    WHERE month_start >= '2005-01-01'
      AND month_start < '2006-01-01'
),
country_month_counts AS (
    SELECT
        country_id,
        month_start,
        payment_count,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, month_start
            ORDER BY payment_count
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY country_id, month_start
        ) AS cnt
    FROM payments_2005
),
country_month_median AS (
    SELECT
        country_id,
        month_start,
        AVG(payment_count * 1.0) AS median_payment_count
    FROM country_month_counts
    WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY
        country_id,
        month_start
),
ranked_payments AS (
    SELECT
        p.*,
        cmm.median_payment_count,
        RANK() OVER (
            PARTITION BY p.country_id, p.month_start
            ORDER BY p.monthly_amount DESC
        ) AS country_month_amount_rank
    FROM payments_2005 AS p
    JOIN country_month_median AS cmm
        ON cmm.country_id = p.country_id
       AND cmm.month_start = p.month_start
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    strftime('%Y-%m', month_start) AS payment_month,
    ROUND(monthly_amount, 2) AS monthly_amount,
    payment_count,
    ROUND(previous_avg_monthly_amount, 2) AS previous_avg_monthly_amount,
    ROUND(monthly_amount - previous_avg_monthly_amount, 2) AS deviation_from_previous_avg,
    ROUND(monthly_amount / NULLIF(previous_avg_monthly_amount, 0), 2) AS ratio_to_previous_avg,
    ROUND(median_payment_count, 2) AS country_month_median_payment_count,
    staff_count,
    store_count,
    country_month_amount_rank
FROM ranked_payments
WHERE previous_month_count > 0
  AND previous_avg_monthly_amount > 0
  AND monthly_amount >= 3.0 * previous_avg_monthly_amount
  AND payment_count > median_payment_count
  AND (staff_count > 1 OR store_count > 1)
ORDER BY
    month_start,
    country_name,
    country_month_amount_rank,
    monthly_amount DESC,
    customer_id;