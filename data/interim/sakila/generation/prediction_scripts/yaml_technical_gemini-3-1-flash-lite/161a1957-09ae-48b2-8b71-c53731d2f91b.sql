WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS activity_date,
        COUNT(*) AS daily_payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_list
    FROM pay AS p
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
        c.c01 AS country_id,
        da.daily_amount
    FROM daily_activity AS da
    JOIN cus ON cus.h01 = da.customer_id
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt AS c ON c.c01 = cty.d03
),
country_p95 AS (
    SELECT
        country_id,
        MAX(daily_amount) AS p95_threshold
    FROM (
        SELECT country_id, daily_amount,
               PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY daily_amount) as pr
        FROM country_stats
    )
    WHERE pr <= 0.95
    GROUP BY country_id
)
SELECT
    da.customer_id,
    cus.h03 || ' ' || cus.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    da.activity_date,
    da.daily_payment_count,
    ROUND(da.daily_amount, 2) AS daily_amount,
    da.staff_list,
    ROUND(da.daily_amount - COALESCE(da.avg_prev_30d, 0), 2) AS deviation_from_avg,
    RANK() OVER (
        PARTITION BY cnt.c01 
        ORDER BY da.daily_amount DESC
    ) AS country_rank
FROM daily_with_history AS da
JOIN cus ON cus.h01 = da.customer_id
JOIN adr ON adr.e01 = cus.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN country_p95 AS cp ON cp.country_id = cnt.c01
WHERE da.daily_amount > COALESCE(da.avg_prev_30d, 0) * 3
  AND da.daily_amount > cp.p95_threshold
ORDER BY cnt.c02, country_rank;