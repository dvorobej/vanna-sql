WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS customer_country,
        cty.d02 AS customer_city
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
),
daily_payment AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT COALESCE(inv.n03, stf.o07)) AS distinct_store_count
    FROM pay AS p
    JOIN stf
        ON stf.o01 = p.p03
    LEFT JOIN ren
        ON ren.q01 = p.p04
    LEFT JOIN inv
        ON inv.n01 = ren.q03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp_prev.day_amount)
            FROM daily_payment AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_date >= date(dp.payment_date, '-30 days')
              AND dp_prev.payment_date < dp.payment_date
        ) AS avg_daily_amount_prev_30d
    FROM daily_payment AS dp
),
suspicious AS (
    SELECT
        dwh.*,
        (dwh.day_amount - dwh.avg_daily_amount_prev_30d) AS excess_amount
    FROM daily_with_history AS dwh
    WHERE dwh.avg_daily_amount_prev_30d IS NOT NULL
      AND dwh.avg_daily_amount_prev_30d > 0
      AND dwh.day_amount >= 3.0 * dwh.avg_daily_amount_prev_30d
      AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
),
ranked AS (
    SELECT
        s.*,
        RANK() OVER (
            PARTITION BY s.customer_id
            ORDER BY s.excess_amount DESC
        ) AS suspicion_rank
    FROM suspicious AS s
)
SELECT
    r.customer_id,
    cg.customer_name,
    cg.customer_country,
    cg.customer_city,
    r.payment_date AS anomaly_date,
    r.payment_count,
    ROUND(r.day_amount, 2) AS day_amount,
    r.distinct_staff_count AS involved_staff_count,
    ROUND(r.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
    r.suspicion_rank
FROM ranked AS r
JOIN customer_geo AS cg
    ON cg.customer_id = r.customer_id
ORDER BY
    r.customer_id,
    r.suspicion_rank,
    r.payment_date;