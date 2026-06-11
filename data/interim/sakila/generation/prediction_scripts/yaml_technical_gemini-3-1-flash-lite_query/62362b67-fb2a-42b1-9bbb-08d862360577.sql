WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
activity_with_history AS (
    SELECT
        da.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_activity AS prev
            WHERE prev.customer_id = da.customer_id
              AND prev.payment_date >= DATE(da.payment_date, '-30 days')
              AND prev.payment_date < da.payment_date
        ) AS avg_prev_30d
    FROM daily_activity AS da
),
suspicious_cases AS (
    SELECT
        da.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        da.day_amount - da.avg_prev_30d AS excess_amount
    FROM activity_with_history AS da
    JOIN cus AS c ON c.h01 = da.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE da.avg_prev_30d IS NOT NULL
      AND da.day_amount >= 3.0 * da.avg_prev_30d
      AND (da.staff_count > 1 OR da.store_count > 1)
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    day_amount,
    payment_count,
    (CASE WHEN staff_count > store_count THEN staff_count ELSE store_count END) AS involved_entities_count,
    ROUND(avg_prev_30d, 2) AS avg_prev_30d,
    RANK() OVER (ORDER BY excess_amount DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY suspicion_rank;