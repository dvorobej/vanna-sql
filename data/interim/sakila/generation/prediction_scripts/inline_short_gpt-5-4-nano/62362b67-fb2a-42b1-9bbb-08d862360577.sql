WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        ct.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS ct
        ON ct.c01 = ci.d03
),
daily_by_customer AS (
    SELECT
        cg.customer_id,
        cg.first_name,
        cg.last_name,
        cg.country,
        cg.city,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN customer_geo AS cg
        ON cg.customer_id = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        cg.customer_id,
        cg.first_name,
        cg.last_name,
        cg.country,
        cg.city,
        DATE(p.p06)
),
daily_with_prev_avg AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.daily_sum)
            FROM daily_by_customer AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= date(d.payment_date, '-30 days')
              AND d2.payment_date < d.payment_date
        ) AS avg_daily_prev_30d
    FROM daily_by_customer AS d
)
SELECT
    dpa.customer_id,
    dpa.first_name,
    dpa.last_name,
    dpa.country,
    dpa.city,
    dpa.payment_date,
    ROUND(dpa.daily_sum, 2) AS daily_sum,
    dpa.payment_count,
    dpa.staff_count,
    dpa.store_count,
    ROUND(dpa.daily_sum / NULLIF(dpa.avg_daily_prev_30d, 0), 2) AS suspicion_multiplier,
    RANK() OVER (
        PARTITION BY dpa.country
        ORDER BY (dpa.daily_sum / NULLIF(dpa.avg_daily_prev_30d, 0)) DESC, dpa.daily_sum DESC
    ) AS suspicion_rank_in_country
FROM daily_with_prev_avg AS dpa
WHERE dpa.avg_daily_prev_30d IS NOT NULL
  AND dpa.avg_daily_prev_30d > 0
  AND dpa.daily_sum >= 3.0 * dpa.avg_daily_prev_30d
ORDER BY
    dpa.country,
    suspicion_rank_in_country,
    dpa.payment_date,
    dpa.customer_id;