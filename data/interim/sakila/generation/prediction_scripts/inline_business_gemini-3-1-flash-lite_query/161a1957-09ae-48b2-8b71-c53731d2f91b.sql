WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        SUM(p.p05) AS daily_sum,
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
              AND h.pay_date >= date(dp.pay_date, '-30 days')
              AND h.pay_date < dp.pay_date
        ) AS avg_prev_30
    FROM daily_payments AS dp
),
country_stats AS (
    SELECT
        c.c01 AS country_id,
        dp.daily_sum
    FROM daily_payments AS dp
    JOIN cus ON cus.h01 = dp.customer_id
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt AS c ON c.c01 = cty.d03
),
country_p95 AS (
    SELECT country_id, MAX(daily_sum) AS p95_val
    FROM (
        SELECT country_id, daily_sum,
               PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY daily_sum) as pr
        FROM country_stats
    ) WHERE pr <= 0.95
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        ch.*,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        (ch.daily_sum - ch.avg_prev_30) AS deviation
    FROM customer_history AS ch
    JOIN cus ON cus.h01 = ch.customer_id
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN country_p95 AS cp ON cp.country_id = cnt.c01
    WHERE ch.payment_count >= 3
      AND (ch.staff_count > 1 OR ch.store_count > 1)
      AND ch.avg_prev_30 > 0
      AND ch.daily_sum >= 2 * ch.avg_prev_30
      AND ch.daily_sum > cp.p95_val
)
SELECT
    customer_name,
    country,
    city,
    pay_date,
    payment_count,
    ROUND(daily_sum, 2) AS daily_sum,
    staff_list,
    ROUND(deviation, 2) AS deviation,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS suspicion_rank
FROM suspicious_cases
ORDER BY country, suspicion_rank;