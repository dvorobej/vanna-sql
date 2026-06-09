WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        COUNT(DISTINCT date(p.p06)) AS distinct_days_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    WHERE p.p04 IS NOT NULL
    GROUP BY
        p.p02,
        c.h03,
        c.h04,
        co.c02,
        ci.d02,
        strftime('%Y-%m', p.p06)
),
with_prev_avg AS (
    SELECT
        mp.*,
        AVG(mp.monthly_sum) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_prev_months_avg
    FROM monthly_payments AS mp
),
suspicious_months AS (
    SELECT *
    FROM with_prev_avg
    WHERE personal_prev_months_avg IS NOT NULL
      AND personal_prev_months_avg > 0
      AND monthly_sum >= 3 * personal_prev_months_avg
      AND payment_count >= 3
      AND distinct_days_count >= 3
      AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
),
ranked AS (
    SELECT
        sm.*,
        RANK() OVER (
            PARTITION BY sm.country_name, sm.payment_month
            ORDER BY sm.monthly_sum DESC
        ) AS country_month_rank
    FROM suspicious_months AS sm
)
SELECT
    payment_month AS month,
    first_name || ' ' || last_name AS customer_fio,
    country_name AS country,
    city_name AS city,
    payment_count AS payments_count,
    ROUND(monthly_sum, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / NULLIF(monthly_sum, 0), 4) AS max_payment_share,
    distinct_staff_count AS different_staff_count,
    distinct_store_count AS different_store_count,
    country_month_rank AS country_month_rank
FROM ranked
ORDER BY
    country,
    month,
    country_month_rank,
    customer_id;