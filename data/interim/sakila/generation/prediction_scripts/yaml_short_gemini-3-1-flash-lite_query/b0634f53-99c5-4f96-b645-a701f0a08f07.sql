WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT s.o07) AS store_ids
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS customer_country,
        cty.d02 AS customer_city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
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
              AND p2.p06 >= datetime(dp.payment_date, '-30 days')
              AND p2.p06 < dp.payment_date
        ) AS avg_daily_amount_30d
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
      AND dp.store_count > 1
),
filtered_suspicious AS (
    SELECT
        sd.*,
        (SELECT GROUP_CONCAT(DISTINCT cnt.c02)
         FROM sto
         JOIN adr ON adr.e01 = sto.j03
         JOIN cty ON cty.d01 = adr.e05
         JOIN cnt ON cnt.c01 = cty.d03
         WHERE instr(',' || sd.store_ids || ',', ',' || sto.j01 || ',') > 0
        ) AS store_countries
    FROM suspicious_days AS sd
    WHERE sd.day_amount >= 2 * sd.avg_daily_amount_30d
),
final_selection AS (
    SELECT
        fs.*,
        (fs.day_amount / NULLIF(fs.avg_daily_amount_30d, 0)) AS exceed_ratio
    FROM filtered_suspicious AS fs
    WHERE fs.store_countries LIKE '%' || fs.customer_country || '%'
      AND fs.store_countries NOT LIKE fs.customer_country -- упрощенная проверка на наличие другой страны
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
    RANK() OVER (PARTITION BY customer_country ORDER BY exceed_ratio DESC) AS suspicion_rank_in_country
FROM final_selection
ORDER BY suspicion_rank_in_country, payment_date;