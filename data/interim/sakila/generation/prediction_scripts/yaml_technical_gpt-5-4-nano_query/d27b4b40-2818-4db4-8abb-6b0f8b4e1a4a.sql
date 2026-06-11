WITH daily_by_customer AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(sto.j01, p.p04)) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN sto ON sto.j01 = i.n03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_prev_avg AS (
    SELECT
        d.*,
        (
            SELECT AVG(CAST(d2.day_sum AS REAL))
            FROM daily_by_customer AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= date(d.payment_date, '-30 days')
              AND d2.payment_date < d.payment_date
        ) AS avg_prev_30d_day_sum
    FROM daily_by_customer AS d
),
suspicious_days AS (
    SELECT
        d.*,
        (d.day_sum / NULLIF(d.avg_prev_30d_day_sum, 0)) AS exceed_ratio
    FROM daily_with_prev_avg AS d
    WHERE d.avg_prev_30d_day_sum IS NOT NULL
      AND d.avg_prev_30d_day_sum > 0
      AND d.day_sum >= 3.0 * d.avg_prev_30d_day_sum
      AND d.payment_count >= 3
      AND (d.staff_count >= 2 OR d.store_count >= 2)
),
ranked_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.day_sum DESC
        ) AS day_amount_rank
    FROM suspicious_days AS sd
)
SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    ci.d02 AS city,
    rd.payment_date,
    rd.payment_count,
    ROUND(rd.day_sum, 2) AS day_sum,
    ROUND(rd.avg_prev_30d_day_sum, 2) AS avg_prev_30d_day_sum,
    ROUND(rd.exceed_ratio, 4) AS exceed_ratio,
    rd.day_amount_rank
FROM ranked_days AS rd
JOIN cus AS c ON c.h01 = rd.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty AS ci ON ci.d01 = a.e05
JOIN cnt AS cnt ON cnt.c01 = ci.d03
ORDER BY
    rd.customer_id,
    rd.day_amount_rank,
    rd.payment_date;