WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p06 AS payment_date,
        date(p.p06, 'start of month') AS month_start,
        strftime('%Y-%m', p.p06) AS calendar_month,
        cu.h02 AS store_id,
        cu.h03 AS customer_first_name,
        cu.h04 AS customer_last_name,
        cu.h05 AS customer_email,
        cu.h07 AS customer_active,
        co.c01 AS country_id,
        co.c02 AS country_name
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = cu.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
monthly_customer AS (
    SELECT
        customer_id,
        store_id,
        customer_first_name,
        customer_last_name,
        customer_email,
        customer_active,
        country_id,
        country_name,
        month_start,
        calendar_month,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS month_total_amount,
        AVG(payment_amount) AS avg_payment_amount,
        COUNT(DISTINCT date(payment_date)) AS payment_days_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        store_id,
        customer_first_name,
        customer_last_name,
        customer_email,
        customer_active,
        country_id,
        country_name,
        month_start,
        calendar_month
),
country_avg AS (
    SELECT
        country_id,
        AVG(month_total_amount) AS country_avg_month_total_amount
    FROM monthly_customer
    GROUP BY country_id
),
staff_monthly AS (
    SELECT
        customer_id,
        month_start,
        staff_id,
        COUNT(*) AS staff_payment_count,
        SUM(payment_amount) AS staff_payment_amount
    FROM payment_enriched
    GROUP BY
        customer_id,
        month_start,
        staff_id
),
top_staff AS (
    SELECT
        customer_id,
        month_start,
        staff_id,
        staff_payment_count,
        staff_payment_amount
    FROM (
        SELECT
            sm.*,
            ROW_NUMBER() OVER (
                PARTITION BY sm.customer_id, sm.month_start
                ORDER BY sm.staff_payment_amount DESC, sm.staff_payment_count DESC, sm.staff_id
            ) AS rn
        FROM staff_monthly AS sm
    )
    WHERE rn = 1
),
monthly_scored AS (
    SELECT
        mc.*,
        prev.month_total_amount AS previous_month_total_amount,
        ca.country_avg_month_total_amount,
        RANK() OVER (
            PARTITION BY mc.country_id, mc.month_start
            ORDER BY mc.month_total_amount DESC
        ) AS country_month_payment_rank
    FROM monthly_customer AS mc
    LEFT JOIN monthly_customer AS prev
        ON prev.customer_id = mc.customer_id
       AND prev.month_start = date(mc.month_start, '-1 month')
    JOIN country_avg AS ca
        ON ca.country_id = mc.country_id
)
SELECT
    ms.calendar_month,
    ms.customer_id,
    ms.customer_first_name,
    ms.customer_last_name,
    ms.customer_email,
    ms.customer_active,
    ms.country_id,
    ms.country_name,
    ms.store_id,
    ms.payment_count,
    ROUND(ms.month_total_amount, 2) AS month_total_amount,
    ROUND(ms.avg_payment_amount, 2) AS avg_payment_amount,
    ms.payment_days_count,
    ROUND(ms.previous_month_total_amount, 2) AS previous_month_total_amount,
    CASE
        WHEN ms.previous_month_total_amount > 0
        THEN ROUND(ms.month_total_amount / ms.previous_month_total_amount, 2)
    END AS growth_vs_previous_month_ratio,
    ROUND(ms.country_avg_month_total_amount, 2) AS country_avg_month_total_amount,
    CASE
        WHEN ms.country_avg_month_total_amount > 0
        THEN ROUND(ms.month_total_amount / ms.country_avg_month_total_amount, 2)
    END AS ratio_vs_country_avg,
    ms.country_month_payment_rank,
    ts.staff_id AS top_staff_id,
    st.o02 AS top_staff_first_name,
    st.o03 AS top_staff_last_name,
    ts.staff_payment_count AS top_staff_payment_count,
    ROUND(ts.staff_payment_amount, 2) AS top_staff_payment_amount
FROM monthly_scored AS ms
JOIN top_staff AS ts
    ON ts.customer_id = ms.customer_id
   AND ts.month_start = ms.month_start
JOIN stf AS st
    ON st.o01 = ts.staff_id
WHERE
    (
        ms.previous_month_total_amount > 0
        AND ms.month_total_amount >= ms.previous_month_total_amount * 3
    )
    OR (
        ms.country_avg_month_total_amount > 0
        AND ms.month_total_amount > ms.country_avg_month_total_amount * 2
    )
ORDER BY
    ms.month_start,
    ms.country_name,
    ms.country_month_payment_rank,
    ms.month_total_amount DESC;