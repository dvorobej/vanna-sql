WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS activity_date,
        COUNT(*) AS daily_payment_count,
        SUM(p.p05) AS daily_amount,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_list,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(i.n03, s.o07)) AS store_count
    FROM pay AS p
    LEFT JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    GROUP BY p.p02, date(p.p06)
    HAVING daily_payment_count >= 3 
       AND (staff_count > 1 OR store_count > 1)
),
daily_with_history AS (
    SELECT
        da.*,
        (
            SELECT AVG(h.daily_amount)
            FROM daily_activity AS h
            WHERE h.customer_id = da.customer_id
              AND h.activity_date >= date(da.activity_date, '-30 days')
              AND h.activity_date < da.activity_date
        ) AS avg_prev_30d
    FROM daily_activity AS da
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
ranked_daily AS (
    SELECT
        dwh.*,
        cs.country_name,
        cs.city_name,
        dwh.daily_amount - COALESCE(dwh.avg_prev_30d, 0) AS deviation,
        PERCENT_RANK() OVER (
            PARTITION BY cs.country_id, dwh.activity_date 
            ORDER BY dwh.daily_amount
        ) AS country_percentile
    FROM daily_with_history AS dwh
    JOIN country_stats AS cs ON cs.customer_id = dwh.customer_id
)
SELECT
    customer_id,
    country_name,
    city_name,
    activity_date,
    daily_payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    staff_list,
    ROUND(deviation, 2) AS deviation_from_avg,
    ROUND(country_percentile, 4) AS country_rank_percentile
FROM ranked_daily
WHERE country_percentile >= 0.95
ORDER BY country_name, activity_date, daily_amount DESC;