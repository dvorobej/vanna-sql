WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
),
daily_customer AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
with_history AS (
    SELECT
        dc.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= date(dc.payment_day, '-30 days')
              AND prev.payment_day <  dc.payment_day
        ) AS avg_prev_30d
    FROM daily_customer AS dc
),
suspicious AS (
    SELECT
        wh.*,
        (wh.day_amount - wh.avg_prev_30d) AS excess_amount
    FROM with_history AS wh
    WHERE wh.avg_prev_30d IS NOT NULL
      AND wh.avg_prev_30d > 0
      AND wh.day_amount >= 3.0 * wh.avg_prev_30d
      AND (wh.distinct_staff_count > 1 OR wh.distinct_store_count > 1)
)
SELECT
    cg.customer_id,
    cg.country,
    cg.city,
    s.payment_day AS suspicious_date,
    s.day_amount AS total_amount_day,
    s.payment_count,
    s.distinct_staff_count AS staff_count,
    s.avg_prev_30d AS avg_daily_amount_prev_30d,
    RANK() OVER (
        ORDER BY s.excess_amount DESC
    ) AS suspicion_rank
FROM suspicious AS s
JOIN customer_geo AS cg
  ON cg.customer_id = s.customer_id
ORDER BY
  suspicion_rank,
  cg.customer_id,
  s.payment_day;