WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country,
        ct.d02  AS city
    FROM cus AS c
    JOIN adr AS a   ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = ct.d03
),
daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
scored AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.daily_sum)
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= date(d.payment_date, '-30 days')
              AND d2.payment_date <  d.payment_date
        ) AS avg_prev_30d
    FROM daily AS d
),
suspicious_days AS (
    SELECT
        s.*,
        (s.daily_sum / s.avg_prev_30d) AS exceed_factor
    FROM scored AS s
    WHERE s.avg_prev_30d IS NOT NULL
      AND s.avg_prev_30d > 0
      AND s.payment_count >= 3
      AND s.daily_sum >= 3.0 * s.avg_prev_30d
      AND (s.staff_count >= 2 OR s.store_count >= 2)
),
ranked AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.daily_sum DESC
        ) AS day_rank_by_sum
    FROM suspicious_days AS sd
)
SELECT
    r.customer_id,
    cg.country,
    cg.city,
    r.payment_date,
    r.payment_count,
    ROUND(r.daily_sum, 2) AS daily_sum,
    ROUND(r.avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(r.exceed_factor, 4) AS exceed_factor,
    r.day_rank_by_sum
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
    r.customer_id,
    r.day_rank_by_sum,
    r.payment_date;