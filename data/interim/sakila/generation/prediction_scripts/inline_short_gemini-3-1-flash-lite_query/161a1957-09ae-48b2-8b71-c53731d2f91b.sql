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
customer_stats AS (
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
country_percentiles AS (
    SELECT
        cg.country_id,
        MAX(CASE WHEN rn >= (0.95 * total_count) THEN day_amount END) AS p95_amount
    FROM (
        SELECT
            c.h01,
            cnt.c01 AS country_id,
            dp.day_amount,
            ROW_NUMBER() OVER (PARTITION BY cnt.c01 ORDER BY dp.day_amount) AS rn,
            COUNT(*) OVER (PARTITION BY cnt.c01) AS total_count
        FROM daily_payments dp
        JOIN cus c ON c.h01 = dp.customer_id
        JOIN adr a ON a.e01 = c.h06
        JOIN cty ct ON ct.d01 = a.e05
        JOIN cnt ON cnt.c01 = ct.d03
    ) cg
    GROUP BY cg.country_id
),
suspicious_cases AS (
    SELECT
        cs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        ct.d02 AS city,
        cnt.c01 AS country_id,
        (cs.day_amount - cs.avg_30d) AS deviation
    FROM customer_stats cs
    JOIN cus c ON c.h01 = cs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
    JOIN country_percentiles cp ON cp.country_id = cnt.c01
    WHERE cs.payment_count >= 3
      AND (cs.staff_count > 1 OR cs.store_count > 1)
      AND cs.avg_30d > 0
      AND cs.day_amount >= 2 * cs.avg_30d
      AND cs.day_amount > cp.p95_amount
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_list,
    ROUND(deviation, 2) AS deviation_from_avg,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country, suspicion_rank;