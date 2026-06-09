WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT s.o02 || ' ' || s.o03) AS staff_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS avg_30d
    FROM daily_payments AS dp
),
country_stats AS (
    SELECT
        cg.country_id,
        dp.day_amount,
        PERCENT_RANK() OVER (PARTITION BY cg.country_id ORDER BY dp.day_amount) AS p_rank
    FROM daily_payments AS dp
    JOIN (
        SELECT c.h01 AS customer_id, cnt.c01 AS country_id
        FROM cus AS c
        JOIN adr AS a ON a.e01 = c.h06
        JOIN cty AS ct ON ct.d01 = a.e05
        JOIN cnt ON cnt.c01 = ct.d03
    ) AS cg ON cg.customer_id = dp.customer_id
),
p95_thresholds AS (
    SELECT country_id, MIN(day_amount) AS p95_val
    FROM country_stats
    WHERE p_rank >= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        ct.d02 AS city,
        cnt.c01 AS country_id,
        (ch.day_amount - ch.avg_30d) AS deviation
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
    JOIN p95_thresholds AS p95 ON p95.country_id = cnt.c01
    WHERE ch.payment_count >= 3
      AND (ch.staff_count > 1 OR ch.store_count > 1)
      AND ch.avg_30d > 0
      AND ch.day_amount >= 2 * ch.avg_30d
      AND ch.day_amount > p95.p95_val
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_list,
    ROUND(deviation, 2) AS deviation,
    DENSE_RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country, suspicion_rank;