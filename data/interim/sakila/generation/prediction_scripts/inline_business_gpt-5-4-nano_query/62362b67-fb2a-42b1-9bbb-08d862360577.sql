WITH payment_daily AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        date(p.p06) AS payment_day,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
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
    GROUP BY
        p.p02,
        c.h03, c.h04,
        co.c02, ci.d02,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        pd.*,
        (
            SELECT AVG(pd_prev.day_amount)
            FROM payment_daily AS pd_prev
            WHERE pd_prev.customer_id = pd.customer_id
              AND pd_prev.payment_day >= date(pd.payment_day, '-30 days')
              AND pd_prev.payment_day < pd.payment_day
        ) AS avg_prev_30d_day_amount
    FROM payment_daily AS pd
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.day_amount - dwh.avg_prev_30d_day_amount) AS excess_amount
    FROM daily_with_history AS dwh
    WHERE dwh.avg_prev_30d_day_amount IS NOT NULL
      AND dwh.avg_prev_30d_day_amount > 0
      AND dwh.day_amount >= 3.0 * dwh.avg_prev_30d_day_amount
      AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
)
SELECT
    sd.customer_id,
    sd.first_name,
    sd.last_name,
    sd.country_name,
    sd.city_name,
    sd.payment_day AS suspicious_date,
    ROUND(sd.day_amount, 2) AS day_amount,
    sd.payment_count,
    sd.distinct_staff_count,
    ROUND(sd.avg_prev_30d_day_amount, 2) AS avg_prev_30d_day_amount,
    RANK() OVER (ORDER BY sd.excess_amount DESC, sd.day_amount DESC, sd.customer_id) AS suspicious_rank
FROM suspicious_days AS sd
ORDER BY
    suspicious_rank,
    sd.day_amount DESC,
    sd.customer_id,
    sd.payment_day;