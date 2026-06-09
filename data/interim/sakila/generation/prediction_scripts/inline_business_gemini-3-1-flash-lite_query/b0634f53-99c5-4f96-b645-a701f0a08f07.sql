WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT cnt_sto.c02) AS store_countries
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto ON sto.j01 = s.o07
    JOIN adr AS adr_sto ON adr_sto.e01 = sto.j03
    JOIN cty AS cty_sto ON cty_sto.d01 = adr_sto.e05
    JOIN cnt AS cnt_sto ON cnt_sto.c01 = cty_sto.d03
    WHERE strftime('%Y', p.p06) = '2005'
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS customer_country
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
suspicious_days AS (
    SELECT
        dp.*,
        cg.customer_name,
        cg.customer_country,
        (
            SELECT SUM(p2.p05) / 30.0
            FROM pay AS p2
            WHERE p2.p02 = dp.customer_id
              AND date(p2.p06) >= date(dp.payment_date, '-30 days')
              AND date(p2.p06) < dp.payment_date
        ) AS avg_prev_30d
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
      AND dp.store_count > 1
      AND dp.store_countries LIKE '%' || ',' || '%' -- упрощенная проверка на разные магазины
      AND dp.store_countries NOT LIKE '%' || cg.customer_country || '%' -- проверка на магазин в другой стране
)
SELECT
    customer_id,
    customer_name,
    payment_date,
    customer_country,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_prev_30d, 2) AS avg_prev_30d,
    staff_count,
    store_count,
    store_countries,
    RANK() OVER (
        PARTITION BY customer_country
        ORDER BY (day_amount / NULLIF(avg_prev_30d, 0)) DESC
    ) AS suspicion_rank_in_country
FROM suspicious_days
WHERE day_amount >= 2 * avg_prev_30d
ORDER BY customer_country, suspicion_rank_in_country;