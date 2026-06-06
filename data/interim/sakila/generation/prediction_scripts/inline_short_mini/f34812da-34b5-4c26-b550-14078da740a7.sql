WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        st.o07 AS store_id,
        p.p05 AS amount,
        p.p06 AS payment_date
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN stf AS st ON st.o01 = p.p03
),
monthly_customer AS (
    SELECT
        customer_id,
        customer_name,
        country_name,
        city_name,
        payment_month,
        COUNT(*) AS payment_count,
        SUM(amount) AS monthly_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count
    FROM payment_base
    GROUP BY
        customer_id,
        customer_name,
        country_name,
        city_name,
        payment_month
),
country_month_avg AS (
    SELECT
        country_name,
        payment_month,
        AVG(monthly_amount) AS avg_country_month_amount
    FROM monthly_customer
    GROUP BY country_name, payment_month
),
return_stats AS (
    SELECT
        c.h01 AS customer_id,
        strftime('%Y-%m', r.q02) AS rental_month,
        AVG(CASE WHEN r.q05 IS NULL OR r.q05 > datetime(r.q02, '+7 days') THEN 1.0 ELSE 0.0 END) AS overdue_return_share
    FROM ren AS r
    JOIN cus AS c ON c.h01 = r.q04
    WHERE strftime('%Y', r.q02) = '2005'
    GROUP BY c.h01, strftime('%Y-%m', r.q02)
),
ranked AS (
    SELECT
        mc.*,
        cma.avg_country_month_amount,
        COALESCE(rs.overdue_return_share, 0) AS overdue_return_share,
        RANK() OVER (
            PARTITION BY mc.country_name, mc.payment_month
            ORDER BY mc.monthly_amount DESC
        ) AS country_rank
    FROM monthly_customer AS mc
    JOIN country_month_avg AS cma
      ON cma.country_name = mc.country_name
     AND cma.payment_month = mc.payment_month
    LEFT JOIN return_stats AS rs
      ON rs.customer_id = mc.customer_id
     AND rs.rental_month = mc.payment_month
)
SELECT
    payment_month AS month,
    country_name AS country,
    city_name AS city,
    customer_name,
    ROUND(monthly_amount, 2) AS total_amount,
    payment_count,
    ROUND(overdue_return_share, 4) AS overdue_return_share,
    country_rank
FROM ranked
WHERE payment_month LIKE '2005-%'
  AND monthly_amount > avg_country_month_amount * 1.5
  AND (distinct_staff_count >= 3 OR distinct_store_count >= 3)
ORDER BY
    country_name,
    payment_month,
    country_rank,
    total_amount DESC;