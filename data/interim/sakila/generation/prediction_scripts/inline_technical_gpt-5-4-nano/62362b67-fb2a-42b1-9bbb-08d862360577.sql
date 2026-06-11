WITH daily_by_customer AS (
    SELECT
        c.h01 AS customer_id,
        date(p.p06) AS payment_day,
        SUM(p.p05) AS day_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.j01) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    LEFT JOIN sto AS s
        ON s.j01 = i.n03
    WHERE p.p06 IS NOT NULL
    GROUP BY
        c.h01,
        date(p.p06)
),
with_history AS (
    SELECT
        d.customer_id,
        d.payment_day,
        d.day_sum,
        d.payment_count,
        d.distinct_staff_count,
        d.distinct_store_count,
        (
            SELECT AVG(d2.day_sum)
            FROM daily_by_customer AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= date(d.payment_day, '-30 days')
              AND d2.payment_day < d.payment_day
        ) AS avg_prev_30d
    FROM daily_by_customer AS d
),
flagged AS (
    SELECT
        wh.*,
        (wh.day_sum / NULLIF(wh.avg_prev_30d, 0)) AS exceed_ratio
    FROM with_history AS wh
    WHERE wh.avg_prev_30d IS NOT NULL
      AND wh.avg_prev_30d > 0
      AND wh.day_sum >= 3 * wh.avg_prev_30d
      AND (wh.distinct_staff_count >= 2 OR wh.distinct_store_count >= 2)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        adr.e01 AS address_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM cus AS c
    JOIN adr
        ON adr.e01 = c.h06
    JOIN cty
        ON cty.d01 = adr.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
)
SELECT
    f.customer_id,
    cg.country,
    cg.city,
    f.payment_day AS suspicious_day,
    f.day_sum,
    f.payment_count,
    f.distinct_staff_count AS staff_count,
    ROUND(f.avg_prev_30d, 2) AS avg_prev_30d,
    DENSE_RANK() OVER (
        ORDER BY (f.day_sum / NULLIF(f.avg_prev_30d, 0)) DESC
    ) AS suspicious_level_rank
FROM flagged AS f
JOIN customer_geo AS cg
    ON cg.customer_id = f.customer_id
ORDER BY
    suspicious_level_rank,
    f.day_sum DESC,
    f.customer_id,
    f.payment_day;