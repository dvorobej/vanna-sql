WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT date(p.p06)) AS payment_days_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st
        ON st.o01 = p.p03
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
monthly_with_prev_avg AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_months_avg_amount
    FROM monthly_payments AS mp
),
monthly_with_geo AS (
    SELECT
        mwa.*,
        c.h03 || ' ' || c.h04 AS customer_full_name,
        cn.c02 AS country,
        ct.d02 AS city,
        cn.c01 AS country_id
    FROM monthly_with_prev_avg AS mwa
    JOIN cus AS c
        ON c.h01 = mwa.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
),
ranked_monthly AS (
    SELECT
        mwg.*,
        RANK() OVER (
            PARTITION BY mwg.country_id, mwg.payment_month
            ORDER BY mwg.total_amount DESC
        ) AS country_month_rank
    FROM monthly_with_geo AS mwg
)
SELECT
    payment_month AS month,
    customer_full_name AS full_name,
    country,
    city,
    payment_count,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / NULLIF(total_amount, 0), 4) AS max_payment_share,
    staff_count,
    store_count,
    country_month_rank
FROM ranked_monthly
WHERE
    prev_months_avg_amount IS NOT NULL
    AND total_amount >= prev_months_avg_amount * 3
    AND payment_count >= 3
    AND payment_days_count >= 3
    AND (staff_count >= 2 OR store_count >= 2)
ORDER BY
    payment_month,
    country,
    country_month_rank,
    total_amount DESC,
    full_name;