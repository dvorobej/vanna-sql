WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_avg AS (
    SELECT
        customer_id,
        AVG(monthly_amount) AS avg_monthly_amount
    FROM monthly_customer_stats
    GROUP BY customer_id
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty AS ci ON a.e05 = ci.d01
    JOIN cnt AS co ON ci.d03 = co.c01
),
monthly_ranked AS (
    SELECT
        mcs.*,
        cs.country_id,
        cs.country_name,
        cs.city_name,
        ca.avg_monthly_amount,
        PERCENT_RANK() OVER (
            PARTITION BY cs.country_id, mcs.payment_month
            ORDER BY mcs.monthly_amount DESC
        ) AS country_percent_rank,
        RANK() OVER (
            PARTITION BY cs.country_id, mcs.payment_month
            ORDER BY mcs.monthly_amount DESC
        ) AS country_rank
    FROM monthly_customer_stats AS mcs
    JOIN customer_avg AS ca ON mcs.customer_id = ca.customer_id
    JOIN country_stats AS cs ON mcs.customer_id = cs.customer_id
),
top_staff_per_month AS (
    SELECT customer_id, payment_month, staff_id
    FROM (
        SELECT
            p.p02 AS customer_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            p.p03 AS staff_id,
            SUM(p.p05) AS staff_amount,
            ROW_NUMBER() OVER (
                PARTITION BY p.p02, strftime('%Y-%m', p.p06)
                ORDER BY SUM(p.p05) DESC
            ) AS rn
        FROM pay AS p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    mr.customer_id,
    mr.country_name,
    mr.city_name,
    mr.payment_month,
    ROUND(mr.monthly_amount, 2) AS monthly_amount,
    mr.payment_count,
    ROUND(mr.monthly_amount - mr.avg_monthly_amount, 2) AS deviation_from_avg,
    mr.country_rank,
    st.o02 AS staff_first_name,
    st.o03 AS staff_last_name
FROM monthly_ranked AS mr
JOIN top_staff_per_month AS ts ON mr.customer_id = ts.customer_id AND mr.payment_month = ts.payment_month
JOIN stf AS st ON ts.staff_id = st.o01
WHERE mr.monthly_amount > 2 * mr.avg_monthly_amount
  AND mr.country_percent_rank <= 0.10
ORDER BY mr.payment_month, mr.country_name, mr.country_rank;