WITH daily_customer_payment AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_total_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        co.c01 AS country_id
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = city.d03
    JOIN stf AS st
        ON st.o01 = p.p03
    JOIN sto AS s
        ON s.j01 = st.o07
    GROUP BY
        p.p02,
        c.h03,
        c.h04,
        date(p.p06),
        co.c01
),
daily_with_baselines AS (
    SELECT
        d.*,
        (
            SELECT AVG(d_prev.day_total_amount)
            FROM daily_customer_payment AS d_prev
            WHERE d_prev.customer_id = d.customer_id
              AND d_prev.payment_day >= date(d.payment_day, '-30 day')
              AND d_prev.payment_day < d.payment_day
        ) AS avg_prev_30d_amount,
        (
            SELECT AVG(d_country.day_total_amount)
            FROM daily_customer_payment AS d_country
            WHERE d_country.country_id = d.country_id
              AND d_country.payment_day >= date(d.payment_day, '-30 day')
              AND d_country.payment_day < d.payment_day
        ) AS avg_country_prev_30d_amount
    FROM daily_customer_payment AS d
),
flagged_days AS (
    SELECT
        *,
        (day_total_amount / NULLIF(avg_prev_30d_amount, 0)) AS ratio_vs_customer_avg_prev_30d,
        (day_total_amount / NULLIF(avg_country_prev_30d_amount, 0)) AS ratio_vs_country_avg_prev_30d
    FROM daily_with_baselines
    WHERE avg_prev_30d_amount IS NOT NULL
      AND avg_country_prev_30d_amount IS NOT NULL
)
SELECT
    customer_id,
    customer_name,
    country_id,
    payment_day,
    payment_count,
    ROUND(day_total_amount, 2) AS day_total_amount,
    distinct_staff_count,
    distinct_store_count,
    ROUND(avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    ROUND(avg_country_prev_30d_amount, 2) AS avg_country_prev_30d_amount,
    ROUND(ratio_vs_customer_avg_prev_30d, 2) AS ratio_vs_customer_avg_prev_30d,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY day_total_amount DESC
    ) AS suspicious_payment_rank_in_country
FROM flagged_days
WHERE day_total_amount > 3.0 * avg_prev_30d_amount
ORDER BY
    country_id,
    suspicious_payment_rank_in_country,
    payment_day,
    customer_id;