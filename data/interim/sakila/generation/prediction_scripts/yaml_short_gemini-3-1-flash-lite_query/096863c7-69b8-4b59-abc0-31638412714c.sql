WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        cnt.c02 AS country
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_with_metrics AS (
    SELECT
        dp.*,
        cg.customer_name,
        cg.city,
        cg.country_id,
        cg.country,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= DATE(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS personal_avg_30d
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
),
country_daily_avg AS (
    SELECT
        cg.country_id,
        AVG(dp.daily_sum) AS country_avg_daily_sum
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    GROUP BY cg.country_id
),
suspicious_cases AS (
    SELECT
        dwm.*,
        cda.country_avg_daily_sum,
        dwm.daily_sum - dwm.personal_avg_30d AS deviation_personal,
        dwm.daily_sum - cda.country_avg_daily_sum AS deviation_country
    FROM daily_with_metrics AS dwm
    JOIN country_daily_avg AS cda ON cda.country_id = dwm.country_id
    WHERE dwm.personal_avg_30d > 0
      AND dwm.daily_sum > 3 * dwm.personal_avg_30d
      AND dwm.daily_sum > cda.country_avg_daily_sum
      AND (dwm.staff_count > 1 OR dwm.store_count > 1)
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    ROUND(daily_sum, 2) AS daily_sum,
    payment_count,
    ROUND(deviation_personal, 2) AS deviation_from_personal_avg,
    ROUND(deviation_country, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY daily_sum DESC
    ) AS country_suspicion_rank
FROM suspicious_cases
ORDER BY country, country_suspicion_rank, payment_date;