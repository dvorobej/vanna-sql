WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    GROUP BY
        p.p02,
        cg.first_name,
        cg.last_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        date(p.p06)
),
daily_with_avgs AS (
    SELECT
        dp.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 day')
              AND prev.payment_date < dp.payment_date
        ) AS personal_avg_30d,
        AVG(dp.day_amount) OVER (
            PARTITION BY dp.country_id, dp.payment_date
        ) AS country_avg_same_day
    FROM daily_payments AS dp
),
suspicious_cases AS (
    SELECT
        *,
        day_amount - personal_avg_30d AS deviation_from_personal_avg,
        day_amount - country_avg_same_day AS deviation_from_country_avg
    FROM daily_with_avgs
    WHERE personal_avg_30d IS NOT NULL
      AND personal_avg_30d > 0
      AND day_amount > personal_avg_30d * 3
      AND day_amount > country_avg_same_day
      AND (staff_count > 1 OR store_count > 1)
),
customer_suspicious_totals AS (
    SELECT
        country_id,
        customer_id,
        SUM(day_amount) AS suspicious_total_amount
    FROM suspicious_cases
    GROUP BY country_id, customer_id
),
ranked_customers AS (
    SELECT
        country_id,
        customer_id,
        DENSE_RANK() OVER (
            PARTITION BY country_id
            ORDER BY suspicious_total_amount DESC
        ) AS customer_country_rank
    FROM customer_suspicious_totals
)
SELECT
    sc.customer_id,
    sc.first_name || ' ' || sc.last_name AS customer_name,
    sc.country_name,
    sc.city_name,
    sc.payment_date,
    ROUND(sc.day_amount, 2) AS day_payment_amount,
    sc.payment_count,
    ROUND(sc.personal_avg_30d, 2) AS personal_avg_30d,
    ROUND(sc.country_avg_same_day, 2) AS country_avg_same_day,
    ROUND(sc.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(sc.deviation_from_country_avg, 2) AS deviation_from_country_avg,
    sc.staff_count,
    sc.store_count,
    rc.customer_country_rank
FROM suspicious_cases AS sc
JOIN ranked_customers AS rc
  ON rc.country_id = sc.country_id
 AND rc.customer_id = sc.customer_id
ORDER BY
    sc.country_name,
    rc.customer_country_rank,
    sc.day_amount DESC,
    sc.payment_date,
    sc.customer_id;