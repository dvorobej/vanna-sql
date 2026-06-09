WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h02 AS store_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS payment_count
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
staff_top AS (
    SELECT * FROM (
        SELECT
            p.p02 AS customer_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            p.p03 AS staff_id,
            s.o02 || ' ' || s.o03 AS staff_name,
            SUM(p.p05) AS staff_sum,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        JOIN stf s ON s.o01 = p.p03
        GROUP BY 1, 2, 3
    ) WHERE rn = 1
),
country_avg AS (
    SELECT
        country_id,
        payment_month,
        AVG(monthly_sum) AS avg_country_sum
    FROM monthly_stats
    GROUP BY 1, 2
),
final_data AS (
    SELECT
        ms.*,
        LAG(ms.monthly_sum) OVER (PARTITION BY ms.customer_id ORDER BY ms.payment_month) AS prev_month_sum,
        ca.avg_country_sum,
        st.staff_name,
        st.staff_sum,
        RANK() OVER (PARTITION BY ms.country_id, ms.payment_month ORDER BY ms.monthly_sum DESC) AS country_rank
    FROM monthly_stats ms
    JOIN country_avg ca ON ca.country_id = ms.country_id AND ca.payment_month = ms.payment_month
    JOIN staff_top st ON st.customer_id = ms.customer_id AND st.payment_month = ms.payment_month
)
SELECT
    payment_month,
    country_name,
    first_name || ' ' || last_name AS customer_name,
    store_id,
    staff_name AS top_staff_name,
    ROUND(monthly_sum, 2) AS monthly_sum,
    payment_count,
    ROUND(prev_month_sum, 2) AS prev_month_sum,
    ROUND(avg_country_sum, 2) AS avg_country_sum,
    country_rank
FROM final_data
WHERE monthly_sum > (COALESCE(prev_month_sum, 0) * 2)
   OR monthly_sum > (avg_country_sum * 3)
ORDER BY payment_month DESC, country_rank ASC;