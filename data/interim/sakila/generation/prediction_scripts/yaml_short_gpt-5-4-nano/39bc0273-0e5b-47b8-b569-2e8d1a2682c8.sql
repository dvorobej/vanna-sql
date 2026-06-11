WITH
monthly_staff AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS store_id,
        c.h01 AS customer_id_check,
        p.p03 AS staff_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        date(p.p06, 'start of month') AS month_start,
        SUM(CAST(p.p05 AS REAL)) AS month_staff_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    GROUP BY
        p.p02,
        c.h02,
        p.p03,
        cn.c01,
        cn.c02,
        date(p.p06, 'start of month')
),
top_customer_month_staff AS (
    SELECT
        ms.*,
        ROW_NUMBER() OVER (
            PARTITION BY ms.country_id, ms.month_start, ms.customer_id, ms.store_id
            ORDER BY ms.month_staff_amount DESC, ms.staff_id
        ) AS rn_staff_within_customer_store_month
    FROM monthly_staff AS ms
),
top_per_customer AS (
    SELECT
        *
    FROM top_customer_month_staff
    WHERE rn_staff_within_customer_store_month = 1
),
country_month_avg AS (
    SELECT
        country_id,
        month_start,
        AVG(month_staff_amount) AS country_avg_monthly_amount,
        COUNT(*) AS country_month_customer_staff_count
    FROM top_per_customer
    GROUP BY country_id, month_start
),
ranked_country AS (
    SELECT
        t.*,
        RANK() OVER (
            PARTITION BY t.country_id, t.month_start
            ORDER BY t.month_staff_amount DESC
        ) AS customer_staff_rank_in_country
    FROM top_per_customer AS t
),
final AS (
    SELECT
        rc.country_id,
        rc.country_name,
        rc.month_start,
        rc.customer_id,
        cu.h03 AS customer_first_name,
        cu.h04 AS customer_last_name,
        rc.store_id,
        rc.staff_id,
        st.o02 AS staff_first_name,
        st.o03 AS staff_last_name,
        rc.month_staff_amount,
        rc.payment_count,
        LAG(rc.month_staff_amount) OVER (
            PARTITION BY rc.country_id, rc.customer_id, rc.store_id, rc.staff_id
            ORDER BY rc.month_start
        ) AS prev_month_amount,
        cma.country_avg_monthly_amount
    FROM ranked_country AS rc
    JOIN cus AS cu
        ON cu.h01 = rc.customer_id
    LEFT JOIN stf AS st
        ON st.o01 = rc.staff_id
    JOIN country_month_avg AS cma
        ON cma.country_id = rc.country_id
       AND cma.month_start = rc.month_start
)
SELECT
    country_id,
    country_name,
    month_start AS month,
    customer_id,
    customer_first_name,
    customer_last_name,
    store_id,
    staff_id,
    staff_first_name,
    staff_last_name,
    ROUND(month_staff_amount, 2) AS month_amount,
    payment_count,
    ROUND(prev_month_amount, 2) AS prev_month_amount,
    ROUND(month_staff_amount - prev_month_amount, 2) AS deviation_from_prev_month,
    ROUND(country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
    ROUND(month_staff_amount - country_avg_monthly_amount, 2) AS deviation_from_country_avg,
    customer_staff_rank_in_country
FROM final
ORDER BY
    country_name,
    month_start,
    customer_staff_rank_in_country,
    customer_id,
    store_id,
    staff_id;