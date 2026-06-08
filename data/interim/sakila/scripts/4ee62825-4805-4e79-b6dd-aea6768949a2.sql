WITH customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 AS first_name,
        cus.h04 AS last_name,
        cus.h07 AS active_status,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        cnt.c02 AS country
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_payments AS (
    SELECT
        cg.customer_id,
        cg.first_name,
        cg.last_name,
        cg.active_status,
        cg.city,
        cg.country_id,
        cg.country,
        date(pay.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(pay.p05) AS total_amount,
        COUNT(DISTINCT pay.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count,
        MIN(pay.p06) AS first_payment_time,
        MAX(pay.p06) AS last_payment_time,
        MAX(pay.p05) AS max_payment_amount
    FROM pay
    JOIN customer_geo AS cg ON cg.customer_id = pay.p02
    JOIN stf ON stf.o01 = pay.p03
    GROUP BY
        cg.customer_id,
        cg.first_name,
        cg.last_name,
        cg.active_status,
        cg.city,
        cg.country_id,
        cg.country,
        date(pay.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(prev.total_amount)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 days')
              AND prev.payment_date < dp.payment_date
        ) AS historical_avg_30d
    FROM daily_payments AS dp
),
country_distribution AS (
    SELECT
        country_id,
        total_amount,
        ROW_NUMBER() OVER (
            PARTITION BY country_id
            ORDER BY total_amount
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY country_id
        ) AS cnt
    FROM daily_payments
),
country_p95 AS (
    SELECT
        country_id,
        MIN(total_amount) AS country_p95_daily_amount
    FROM country_distribution
    WHERE rn >= ((95 * cnt + 99) / 100)
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        dwh.customer_id,
        dwh.first_name,
        dwh.last_name,
        dwh.city,
        dwh.country_id,
        dwh.country,
        dwh.payment_date,
        dwh.payment_count,
        dwh.total_amount,
        dwh.staff_count,
        dwh.store_count,
        dwh.first_payment_time,
        dwh.last_payment_time,
        dwh.max_payment_amount,
        dwh.historical_avg_30d,
        cp.country_p95_daily_amount,
        dwh.total_amount - dwh.historical_avg_30d AS excess_over_historical_avg
    FROM daily_with_history AS dwh
    JOIN country_p95 AS cp ON cp.country_id = dwh.country_id
    WHERE dwh.active_status IN ('1', 'Y', 'y')
      AND dwh.payment_count >= 3
      AND dwh.staff_count >= 2
      AND dwh.historical_avg_30d IS NOT NULL
      AND dwh.total_amount > 3 * dwh.historical_avg_30d
      AND dwh.total_amount > cp.country_p95_daily_amount
)
SELECT
    customer_id,
    first_name,
    last_name,
    city,
    country,
    payment_date,
    payment_count,
    total_amount,
    staff_count,
    store_count,
    first_payment_time,
    last_payment_time,
    max_payment_amount,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY excess_over_historical_avg DESC
    ) AS suspicion_rank_in_country
FROM suspicious_cases
ORDER BY
    country,
    suspicion_rank_in_country,
    total_amount DESC,
    customer_id,
    payment_date;