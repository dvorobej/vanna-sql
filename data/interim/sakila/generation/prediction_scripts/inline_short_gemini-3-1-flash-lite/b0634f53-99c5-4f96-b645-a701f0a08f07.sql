WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
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
        cty.d01 AS city_id,
        cty.d02 AS city_name,
        sto.j01 AS home_store_id,
        sto_cnt.c01 AS home_country_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN sto ON sto.j01 = c.h02
    JOIN adr AS sto_adr ON sto_adr.e01 = sto.j03
    JOIN cty AS sto_cty ON sto_cty.d01 = sto_adr.e05
    JOIN cnt AS sto_cnt ON sto_cnt.c01 = sto_cty.d03
),
suspicious_days AS (
    SELECT
        dp.*,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        (SELECT SUM(prev.day_amount) / 30.0
         FROM daily_payments AS prev
         WHERE prev.customer_id = dp.customer_id
           AND prev.payment_day >= DATE(dp.payment_day, '-30 days')
           AND prev.payment_day < dp.payment_day) AS avg_30d,
        EXISTS (
            SELECT 1 FROM pay AS p2
            JOIN stf AS s2 ON s2.o01 = p2.p03
            JOIN sto AS st2 ON st2.j01 = s2.o07
            JOIN adr AS a2 ON a2.e01 = st2.j03
            JOIN cty AS c2 ON c2.d01 = a2.e05
            WHERE p2.p02 = dp.customer_id 
              AND DATE(p2.p06) = dp.payment_day
              AND c2.d03 <> cg.country_id
        ) AS has_foreign_store_payment
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
      AND dp.staff_count > 1
      AND dp.store_count > 1
      AND dp.day_amount >= 2 * (SELECT SUM(prev.day_amount) / 30.0
                                FROM daily_payments AS prev
                                WHERE prev.customer_id = dp.customer_id
                                  AND prev.payment_day >= DATE(dp.payment_day, '-30 days')
                                  AND prev.payment_day < dp.payment_day)
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    payment_day,
    payment_count,
    day_amount,
    avg_30d,
    day_amount / NULLIF(avg_30d, 0) AS exceed_ratio,
    RANK() OVER (PARTITION BY country_id ORDER BY (day_amount / NULLIF(avg_30d, 0)) DESC) AS country_rank
FROM suspicious_days
WHERE has_foreign_store_payment = 1
ORDER BY country_name, country_rank;