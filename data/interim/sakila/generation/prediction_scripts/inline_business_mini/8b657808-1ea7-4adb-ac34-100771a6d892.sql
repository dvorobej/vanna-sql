WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS pay_month,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS monthly_sum,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT st.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS st
        ON st.o01 = p.p03
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
customer_month_baseline AS (
    SELECT
        mp.*,
        AVG(mp.monthly_sum) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.pay_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3m_avg_sum
    FROM monthly_payments AS mp
),
country_month_profile AS (
    SELECT
        cty.d03 AS country_id,
        strftime('%Y-%m', p.p06) AS pay_month,
        AVG(CAST(p.p05 AS REAL)) AS country_avg_payment_amount
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = cu.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    GROUP BY
        cty.d03,
        strftime('%Y-%m', p.p06)
),
customer_geo AS (
    SELECT
        cu.h01 AS customer_id,
        cu.h03 AS first_name,
        cu.h04 AS last_name,
        cty.d03 AS country_id,
        cnt.c02 AS country_name
    FROM cus AS cu
    JOIN adr AS a
        ON a.e01 = cu.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
),
ranked AS (
    SELECT
        cmb.customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cmb.pay_month,
        cmb.payment_count,
        cmb.monthly_sum,
        cmb.prev_3m_avg_sum,
        cmp.country_avg_payment_amount,
        cmb.distinct_staff_count,
        cmb.distinct_store_count,
        RANK() OVER (
            PARTITION BY cg.country_id, cmb.pay_month
            ORDER BY cmb.monthly_sum DESC
        ) AS country_month_rank
    FROM customer_month_baseline AS cmb
    JOIN customer_geo AS cg
        ON cg.customer_id = cmb.customer_id
    JOIN country_month_profile AS cmp
        ON cmp.country_id = cg.country_id
       AND cmp.pay_month = cmb.pay_month
)
SELECT
    customer_id,
    first_name,
    last_name,
    country_name,
    pay_month,
    payment_count,
    ROUND(monthly_sum, 2) AS monthly_sum,
    ROUND(prev_3m_avg_sum, 2) AS prev_3m_avg_sum,
    ROUND(country_avg_payment_amount, 2) AS country_avg_payment_amount,
    distinct_staff_count,
    distinct_store_count,
    country_month_rank
FROM ranked
WHERE prev_3m_avg_sum IS NOT NULL
  AND monthly_sum >= 2 * prev_3m_avg_sum
  AND monthly_sum >= 2 * country_avg_payment_amount
  AND distinct_staff_count >= 3
ORDER BY
    pay_month,
    country_name,
    country_month_rank,
    monthly_sum DESC;