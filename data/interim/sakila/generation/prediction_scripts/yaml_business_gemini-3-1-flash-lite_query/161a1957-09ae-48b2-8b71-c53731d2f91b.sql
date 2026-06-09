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
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS avg_prev_30d
    FROM daily_payments AS dp
),
country_stats AS (
    SELECT
        c.c01 AS country_id,
        dp.day_amount
    FROM daily_payments AS dp
    JOIN cus AS cu ON cu.h01 = dp.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ct.d03
),
p95_by_country AS (
    SELECT country_id, MAX(day_amount) as p95_val
    FROM (
        SELECT country_id, day_amount,
               PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) as pr
        FROM country_stats
    ) WHERE pr <= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        dp.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        cn.c02 AS country,
        ct.d02 AS city,
        cn.c01 AS country_id,
        (dp.day_amount - dp.avg_prev_30d) AS deviation
    FROM daily_with_history AS dp
    JOIN cus AS cu ON cu.h01 = dp.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN p95_by_country AS p95 ON p95.country_id = cn.c01
    WHERE dp.payment_count >= 3
      AND (dp.staff_count > 1 OR dp.store_count > 1)
      AND dp.avg_prev_30d > 0
      AND dp.day_amount >= 2 * dp.avg_prev_30d
      AND dp.day_amount > p95.p95_val
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
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country, suspicion_rank;