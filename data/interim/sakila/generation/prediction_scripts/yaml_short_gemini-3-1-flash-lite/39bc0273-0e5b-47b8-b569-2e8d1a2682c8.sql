WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h02 AS store_id,
        cn.c01 AS country_id,
        cn.c02 AS country,
        ct.d02 AS city,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
staff_monthly_top AS (
    SELECT * FROM (
        SELECT
            p.p02 AS customer_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            p.p03 AS staff_id,
            s.o02 || ' ' || s.o03 AS staff_name,
            SUM(p.p05) AS staff_amount,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        JOIN stf s ON s.o01 = p.p03
        GROUP BY 1, 2, 3, 4
    ) WHERE rn = 1
),
country_monthly_avg AS (
    SELECT
        country_id,
        payment_month,
        AVG(monthly_amount) AS avg_country_amount
    FROM monthly_stats
    GROUP BY 1, 2
),
enriched_stats AS (
    SELECT
        ms.*,
        LAG(ms.monthly_amount) OVER (PARTITION BY ms.customer_id ORDER BY ms.payment_month) AS prev_month_amount,
        cma.avg_country_amount,
        st.staff_id,
        st.staff_name
    FROM monthly_stats ms
    JOIN country_monthly_avg cma ON cma.country_id = ms.country_id AND cma.payment_month = ms.payment_month
    JOIN staff_monthly_top st ON st.customer_id = ms.customer_id AND st.payment_month = ms.payment_month
)
SELECT
    payment_month,
    country,
    city,
    store_id,
    first_name || ' ' || last_name AS customer_name,
    ROUND(monthly_amount, 2) AS monthly_amount,
    ROUND(prev_month_amount, 2) AS prev_month_amount,
    ROUND(avg_country_amount, 2) AS avg_country_amount,
    staff_name,
    RANK() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_amount DESC) AS country_rank
FROM enriched_stats
WHERE monthly_amount > (COALESCE(prev_month_amount, 0) * 2)
   OR monthly_amount > (avg_country_amount * 3)
ORDER BY payment_month, country, country_rank;