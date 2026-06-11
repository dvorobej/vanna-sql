WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
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
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
suspicious_days AS (
    SELECT
        dp.*,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        (
            SELECT SUM(CAST(p2.p05 AS REAL))
            FROM pay AS p2
            WHERE p2.p02 = dp.customer_id
              AND date(p2.p06) >= date(dp.payment_date, '-30 days')
              AND date(p2.p06) < dp.payment_date
        ) / 30.0 AS avg_daily_amount_prev_30_days
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
      AND dp.store_count > 1
      AND dp.store_countries LIKE '%' || ',' || '%' -- упрощенная проверка на разные страны
      AND dp.store_countries NOT LIKE '%' || cg.country_name || '%'
),
ranked_suspicious AS (
    SELECT
        sd.*,
        (sd.day_amount / NULLIF(sd.avg_daily_amount_prev_30_days, 0)) AS exceed_ratio
    FROM suspicious_days AS sd
    WHERE sd.day_amount >= 2 * sd.avg_daily_amount_prev_30_days
)
SELECT
    customer_name,
    payment_date,
    country_name,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_daily_amount_prev_30_days, 2) AS avg_daily_amount_prev_30_days,
    staff_count,
    store_count,
    store_countries,
    RANK() OVER (PARTITION BY country_id ORDER BY exceed_ratio DESC) AS suspicion_rank_in_country
FROM ranked_suspicious
ORDER BY country_name, suspicion_rank_in_country;