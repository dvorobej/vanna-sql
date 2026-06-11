WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
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
            SELECT AVG(h.daily_sum)
            FROM daily_payments AS h
            WHERE h.customer_id = dp.customer_id
              AND h.payment_date >= date(dp.payment_date, '-30 days')
              AND h.payment_date < dp.payment_date
        ) AS avg_prev_30
    FROM daily_payments AS dp
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
country_p95 AS (
    SELECT
        cs.country_id,
        MAX(val) AS p95_val
    FROM (
        SELECT
            cs.country_id,
            dp.daily_sum AS val,
            PERCENT_RANK() OVER (PARTITION BY cs.country_id ORDER BY dp.daily_sum) AS p_rank
        FROM daily_payments AS dp
        JOIN country_stats AS cs ON cs.customer_id = dp.customer_id
    )
    WHERE p_rank <= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        ch.*,
        cs.country_name,
        cs.city_name,
        (ch.daily_sum - ch.avg_prev_30) AS deviation
    FROM customer_history AS ch
    JOIN country_stats AS cs ON cs.customer_id = ch.customer_id
    JOIN country_p95 AS cp ON cp.country_id = cs.country_id
    WHERE ch.payment_count >= 3
      AND (ch.staff_count > 1 OR ch.store_count > 1)
      AND ch.avg_prev_30 > 0
      AND ch.daily_sum >= 2 * ch.avg_prev_30
      AND ch.daily_sum > cp.p95_val
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    sc.country_name,
    sc.city_name,
    sc.payment_date,
    sc.payment_count,
    ROUND(sc.daily_sum, 2) AS daily_sum,
    sc.staff_list,
    ROUND(sc.deviation, 2) AS deviation,
    RANK() OVER (PARTITION BY sc.country_name ORDER BY sc.deviation DESC) AS suspicion_rank
FROM suspicious_cases AS sc
JOIN cus AS c ON c.h01 = sc.customer_id
ORDER BY sc.country_name, suspicion_rank;