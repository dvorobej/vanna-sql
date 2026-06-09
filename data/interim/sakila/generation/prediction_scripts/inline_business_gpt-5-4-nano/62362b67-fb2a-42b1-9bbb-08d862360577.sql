WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS customer_country,
        cty.d02 AS customer_city,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS daily_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        c.h03,
        c.h04,
        cnt.c02,
        cty.d02,
        DATE(p.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp_prev.daily_amount)
            FROM daily_payments AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_date >= DATE(dp.payment_date, '-30 days')
              AND dp_prev.payment_date < dp.payment_date
        ) AS avg_daily_amount_prev_30d
    FROM daily_payments AS dp
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.daily_amount - dwh.avg_daily_amount_prev_30d) AS excess_amount,
        RANK() OVER (
            PARTITION BY dwh.customer_country
            ORDER BY (dwh.daily_amount / NULLIF(dwh.avg_daily_amount_prev_30d, 0)) DESC
        ) AS suspicion_rank_in_country
    FROM daily_with_history AS dwh
    WHERE dwh.avg_daily_amount_prev_30d IS NOT NULL
      AND dwh.avg_daily_amount_prev_30d > 0
      AND dwh.daily_amount >= 3 * dwh.avg_daily_amount_prev_30d
      AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
)
SELECT
    customer_id,
    customer_name,
    customer_country,
    customer_city,
    payment_date,
    payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    distinct_staff_count AS involved_staff_count,
    ROUND(avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
    suspicion_rank_in_country
FROM suspicious_days
ORDER BY
    customer_country,
    suspicion_rank_in_country,
    daily_amount DESC,
    customer_id,
    payment_date;