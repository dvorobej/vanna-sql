WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        COUNT(DISTINCT CASE WHEN sto.j03 <> adr.e05 THEN sto.j01 END) AS cross_border_store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto AS sto ON sto.j01 = s.o07
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS adr ON adr.e01 = c.h06
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, DATE(p.p06)
),
daily_with_baseline AS (
    SELECT
        dp.*,
        (
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= DATE(dp.payment_date, '-30 day')
              AND prev.payment_date < dp.payment_date
        ) AS avg_30d
    FROM daily_payments AS dp
),
suspicious_days AS (
    SELECT
        swb.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        (swb.day_amount / NULLIF(swb.avg_30d, 0)) AS exceed_ratio
    FROM daily_with_baseline AS swb
    JOIN cus AS c ON c.h01 = swb.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE swb.payment_count >= 3
      AND swb.day_amount >= 2.0 * swb.avg_30d
      AND swb.staff_count > 1
      AND swb.store_count > 1
      AND swb.cross_border_store_count > 0
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_30d, 2) AS avg_30d,
    ROUND(exceed_ratio, 2) AS exceed_ratio,
    RANK() OVER (PARTITION BY country_name ORDER BY exceed_ratio DESC) AS country_rank
FROM suspicious_days
ORDER BY country_name, country_rank;