WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_with_history AS (
    SELECT
        dp.*,
        cg.customer_name,
        cg.country,
        cg.city,
        cg.country_id,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS avg_prev_30d
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
),
country_stats AS (
    SELECT
        country_id,
        day_amount,
        PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) AS p_rank
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
),
p95_thresholds AS (
    SELECT country_id, MIN(day_amount) AS p95_val
    FROM country_stats
    WHERE p_rank >= 0.95
    GROUP BY country_id
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.day_amount - dwh.avg_prev_30d) AS deviation
    FROM daily_with_history AS dwh
    JOIN p95_thresholds AS p95 ON p95.country_id = dwh.country_id
    WHERE dwh.payment_count >= 3
      AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
      AND dwh.avg_prev_30d > 0
      AND dwh.day_amount >= 2 * dwh.avg_prev_30d
      AND dwh.day_amount > p95.p95_val
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_list,
    ROUND(day_amount - avg_prev_30d, 2) AS deviation_from_personal_avg,
    RANK() OVER (PARTITION BY country_id ORDER BY (day_amount - avg_prev_30d) DESC) AS suspicion_rank_in_country
FROM suspicious_days
ORDER BY country, suspicion_rank_in_country;