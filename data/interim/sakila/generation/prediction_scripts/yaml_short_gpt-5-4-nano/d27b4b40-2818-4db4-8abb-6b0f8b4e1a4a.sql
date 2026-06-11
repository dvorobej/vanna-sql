WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
),
daily_pay AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_total_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_prev_avg AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp2.day_total_amount)
            FROM daily_pay AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= date(dp.payment_date, '-30 days')
              AND dp2.payment_date < dp.payment_date
        ) AS avg_prev_30d_amount
    FROM daily_pay AS dp
),
qualified_days AS (
    SELECT
        d.*,
        (d.day_total_amount / NULLIF(d.avg_prev_30d_amount, 0)) AS exceed_multiplier
    FROM daily_with_prev_avg AS d
    WHERE d.avg_prev_30d_amount IS NOT NULL
      AND d.avg_prev_30d_amount > 0
      AND d.day_total_amount >= 3 * d.avg_prev_30d_amount
      AND d.payment_count >= 3
      AND (d.staff_count >= 2 OR d.store_count >= 2)
)
SELECT
    q.customer_name,
    cg.country_name,
    cg.city_name,
    q.payment_date,
    q.payment_count,
    ROUND(q.day_total_amount, 2) AS day_total_amount,
    ROUND(q.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    ROUND(q.exceed_multiplier, 4) AS exceed_multiplier,
    RANK() OVER (
        PARTITION BY q.customer_id
        ORDER BY q.day_total_amount DESC
    ) AS day_rank_by_amount
FROM qualified_days AS q
JOIN customer_geo AS cg
  ON cg.customer_id = q.customer_id
ORDER BY
    cg.country_name,
    cg.city_name,
    q.customer_name,
    day_rank_by_amount,
    q.payment_date;