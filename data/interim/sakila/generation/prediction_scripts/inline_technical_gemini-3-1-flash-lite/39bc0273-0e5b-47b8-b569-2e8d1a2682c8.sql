WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        AVG(p.p05) AS avg_check,
        COUNT(DISTINCT date(p.p06)) AS distinct_payment_days
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mcs.*,
        LAG(mcs.monthly_amount) OVER (PARTITION BY mcs.customer_id ORDER BY mcs.payment_month) AS prev_month_amount
    FROM monthly_customer_stats AS mcs
),
country_monthly_avg AS (
    SELECT
        c.c01 AS country_id,
        mcs.payment_month,
        AVG(mcs.monthly_amount) AS country_avg_monthly_amount
    FROM monthly_customer_stats AS mcs
    JOIN cus AS cu ON cu.h01 = mcs.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ct.d03
    GROUP BY c.c01, mcs.payment_month
),
ranked_customers AS (
    SELECT
        mcs.*,
        c.c01 AS country_id,
        RANK() OVER (PARTITION BY c.c01, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_rank
    FROM monthly_customer_stats AS mcs
    JOIN cus AS cu ON cu.h01 = mcs.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ct.d03
),
staff_top_per_month AS (
    SELECT * FROM (
        SELECT
            p.p02 AS customer_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            p.p03 AS staff_id,
            SUM(p.p05) AS staff_amount,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) AS rn
        FROM pay AS p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    mwh.customer_id,
    cu.h03 || ' ' || cu.h04 AS customer_name,
    cnt.c02 AS country_name,
    cu.h02 AS store_id,
    mwh.payment_month,
    mwh.monthly_amount,
    mwh.payment_count,
    mwh.avg_check,
    mwh.distinct_payment_days,
    rc.country_rank,
    st.staff_id AS top_staff_id,
    st.staff_amount AS top_staff_amount
FROM monthly_with_history AS mwh
JOIN ranked_customers AS rc ON rc.customer_id = mwh.customer_id AND rc.payment_month = mwh.payment_month
JOIN country_monthly_avg AS cma ON cma.country_id = rc.country_id AND cma.payment_month = mwh.payment_month
JOIN cus AS cu ON cu.h01 = mwh.customer_id
JOIN adr AS a ON a.e01 = cu.h06
JOIN cty AS ct ON ct.d01 = a.e05
JOIN cnt ON cnt.c01 = ct.d03
JOIN staff_top_per_month AS st ON st.customer_id = mwh.customer_id AND st.payment_month = mwh.payment_month
WHERE (mwh.prev_month_amount IS NOT NULL AND mwh.monthly_amount >= 3 * mwh.prev_month_amount)
   OR (mwh.monthly_amount > 2 * cma.country_avg_monthly_amount)
ORDER BY mwh.payment_month DESC, mwh.monthly_amount DESC;