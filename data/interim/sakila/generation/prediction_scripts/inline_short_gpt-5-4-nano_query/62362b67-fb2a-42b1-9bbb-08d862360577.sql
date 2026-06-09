WITH daily_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        c.h01, c.h03, c.h04, cnt.c02, cty.d02, date(p.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp_prev.day_amount)
            FROM daily_payments AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_date >= date(dp.payment_date, '-30 day')
              AND dp_prev.payment_date < dp.payment_date
        ) AS avg_prev_30d_day_amount
    FROM daily_payments AS dp
),
suspicious AS (
    SELECT
        dwh.*,
        (dwh.day_amount - dwh.avg_prev_30d_day_amount) AS excess_amount
    FROM daily_with_history AS dwh
    WHERE dwh.avg_prev_30d_day_amount IS NOT NULL
      AND dwh.avg_prev_30d_day_amount > 0
      AND dwh.day_amount >= 3.0 * dwh.avg_prev_30d_day_amount
      AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
)
SELECT
    customer_id,
    first_name,
    last_name,
    country_name,
    city_name,
    payment_date AS suspicious_date,
    ROUND(day_amount, 2) AS day_amount,
    payment_count,
    staff_count AS distinct_staff_count,
    ROUND(avg_prev_30d_day_amount, 2) AS avg_prev_30d_day_amount,
    RANK() OVER (ORDER BY excess_amount DESC) AS suspicious_rank
FROM suspicious
ORDER BY
    suspicious_rank,
    day_amount DESC,
    customer_id;