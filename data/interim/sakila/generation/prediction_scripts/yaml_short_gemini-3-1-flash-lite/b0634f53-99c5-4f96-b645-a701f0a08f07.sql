WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT s.o07) AS store_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
suspicious_days AS (
    SELECT
        da.*,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        (SELECT SUM(da2.day_amount) / 30.0
         FROM daily_activity AS da2
         WHERE da2.customer_id = da.customer_id
           AND da2.payment_date >= DATE(da.payment_date, '-30 days')
           AND da2.payment_date < da.payment_date) AS avg_30d,
        EXISTS (
            SELECT 1 FROM pay AS p
            JOIN stf AS s ON s.o01 = p.p03
            JOIN inv AS i ON i.n03 = s.o07
            JOIN sto AS st ON st.j01 = i.n03
            JOIN adr AS a ON a.e01 = st.j02
            JOIN cty AS ct ON ct.d01 = a.e05
            WHERE p.p02 = da.customer_id 
              AND DATE(p.p06) = da.payment_date
              AND ct.d03 <> cg.country_id
        ) AS has_foreign_store_payment
    FROM daily_activity AS da
    JOIN customer_geo AS cg ON cg.customer_id = da.customer_id
    WHERE da.payment_count >= 3
      AND da.staff_count > 1
      AND da.store_count > 1
      AND has_foreign_store_payment = 1
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    payment_count,
    day_amount,
    ROUND(day_amount / NULLIF(avg_30d, 0), 2) AS exceed_ratio,
    RANK() OVER (PARTITION BY country_id ORDER BY (day_amount / NULLIF(avg_30d, 0)) DESC) AS country_rank
FROM suspicious_days
WHERE day_amount >= 2.0 * avg_30d
ORDER BY country_name, country_rank;