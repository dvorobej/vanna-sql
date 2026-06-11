WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT cnt_store.c02) AS store_countries
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto ON sto.j01 = s.o07
    JOIN adr AS adr_store ON adr_store.e01 = sto.j03
    JOIN cty AS cty_store ON cty_store.d01 = adr_store.e05
    JOIN cnt AS cnt_store ON cnt_store.c01 = cty_store.d03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
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
              AND p2.p06 >= date(dp.payment_date, '-30 days')
              AND p2.p06 < dp.payment_date
        ) AS avg_daily_amount_30d
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
      AND dp.staff_count >= 1
      AND dp.store_count > 1
      AND EXISTS (
          SELECT 1 FROM pay p3
          JOIN stf s3 ON s3.o01 = p3.p03
          JOIN sto sto3 ON sto3.j01 = s3.o07
          JOIN adr adr3 ON adr3.e01 = sto3.j03
          JOIN cty cty3 ON cty3.d01 = adr3.e05
          JOIN cnt cnt3 ON cnt3.c01 = cty3.d03
          WHERE p3.p02 = dp.customer_id 
            AND date(p3.p06) = dp.payment_date
            AND cnt3.c02 <> cg.customer_country
      )
)
SELECT
    customer_id,
    customer_name,
    payment_date,
    customer_country,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_daily_amount_30d, 2) AS avg_daily_amount_30d,
    staff_count,
    store_count,
    store_countries,
    RANK() OVER (
        PARTITION BY customer_country 
        ORDER BY (day_amount / NULLIF(avg_daily_amount_30d, 0)) DESC
    ) AS suspicion_rank_in_country
FROM suspicious_days
WHERE day_amount >= 2 * avg_daily_amount_30d
ORDER BY customer_country, suspicion_rank_in_country;