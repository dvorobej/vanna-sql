WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
),
daily_customer AS (
    SELECT
        cg.customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM pay AS p
    JOIN customer_geo AS cg
        ON cg.customer_id = p.p02
    JOIN stf
        ON stf.o01 = p.p03
    GROUP BY
        cg.customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        date(p.p06)
),
with_history AS (
    SELECT
        dc.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_date >= date(dc.payment_date, '-30 days')
              AND prev.payment_date < dc.payment_date
        ) AS avg_prev_30d
    FROM daily_customer AS dc
),
suspicious AS (
    SELECT
        wh.*,
        (wh.day_amount - wh.avg_prev_30d) / wh.avg_prev_30d AS excess_ratio
    FROM with_history AS wh
    WHERE wh.avg_prev_30d IS NOT NULL
      AND wh.avg_prev_30d > 0
      AND wh.day_amount >= 3.0 * wh.avg_prev_30d
      AND (wh.staff_count > 1 OR wh.store_count > 1)
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
    ROUND(avg_prev_30d, 2) AS avg_daily_amount_prev_30d,
    RANK() OVER (
        ORDER BY excess_ratio DESC, day_amount DESC, customer_id
    ) AS suspicious_rank
FROM suspicious
ORDER BY
    suspicious_rank,
    customer_id,
    payment_date;