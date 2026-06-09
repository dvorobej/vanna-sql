WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT COALESCE(s.j01, -1)) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_prev AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.day_amount)
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= date(d.payment_date, '-30 days')
              AND d2.payment_date < d.payment_date
        ) AS avg_prev_30d_amount
    FROM daily AS d
),
suspicious AS (
    SELECT
        dwp.*,
        (dwp.day_amount / NULLIF(dwp.avg_prev_30d_amount, 0)) AS exceed_ratio
    FROM daily_with_prev AS dwp
    WHERE dwp.avg_prev_30d_amount IS NOT NULL
      AND dwp.avg_prev_30d_amount > 0
      AND dwp.day_amount >= 3.0 * dwp.avg_prev_30d_amount
      AND dwp.payment_count >= 3
      AND (dwp.distinct_staff_count >= 2 OR dwp.distinct_store_count >= 2)
),
ranked AS (
    SELECT
        s.*,
        RANK() OVER (
            PARTITION BY s.customer_id
            ORDER BY s.day_amount DESC
        ) AS day_amount_rank
    FROM suspicious AS s
)
SELECT
    r.customer_id,
    cg.customer_name,
    cg.country,
    cg.city,
    r.payment_date AS suspicious_date,
    r.payment_count,
    ROUND(r.day_amount, 2) AS day_total_amount,
    ROUND(r.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    ROUND(r.exceed_ratio, 4) AS exceed_ratio,
    r.day_amount_rank
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
    cg.country,
    cg.city,
    r.customer_id,
    r.day_amount_rank,
    r.payment_date;