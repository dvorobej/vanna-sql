WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c01 AS country_id,
        co.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.pay_date >= date(dp.pay_date, '-30 days')
              AND prev.pay_date < dp.pay_date
        ) AS avg_prev_30
    FROM daily_payments AS dp
),
country_stats AS (
    SELECT
        cg.country_id,
        dp.daily_sum,
        PERCENT_RANK() OVER (PARTITION BY cg.country_id ORDER BY dp.daily_sum) AS p_rank
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
),
p95_thresholds AS (
    SELECT country_id, MIN(daily_sum) AS p95_val
    FROM country_stats
    WHERE p_rank >= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        dwh.*,
        cg.customer_name,
        cg.country,
        cg.city,
        (dwh.daily_sum - dwh.avg_prev_30) AS deviation
    FROM daily_with_history AS dwh
    JOIN customer_geo AS cg ON cg.customer_id = dwh.customer_id
    JOIN p95_thresholds AS p95 ON p95.country_id = cg.country_id
    WHERE dwh.payment_count >= 3
      AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
      AND dwh.avg_prev_30 > 0
      AND dwh.daily_sum >= 2 * dwh.avg_prev_30
      AND dwh.daily_sum > p95.p95_val
)
SELECT
    customer_name,
    country,
    city,
    pay_date,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    staff_list,
    ROUND(deviation, 2) AS deviation_from_avg,
    RANK() OVER (PARTITION BY country ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country, suspicion_rank;