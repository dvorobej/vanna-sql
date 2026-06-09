WITH daily_by_customer AS (
    SELECT
        c.h01 AS customer_id,
        date(p.p06) AS activity_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.j01) AS store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN sto AS s
        ON s.j01 = i.n03
    GROUP BY
        c.h01,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        d.customer_id,
        d.activity_date,
        d.payment_count,
        d.day_amount,
        d.staff_count,
        d.store_count,
        (
            SELECT AVG(CAST(x.day_amount AS REAL))
            FROM daily_by_customer AS x
            WHERE x.customer_id = d.customer_id
              AND x.activity_date >= date(d.activity_date, '-30 day')
              AND x.activity_date < d.activity_date
        ) AS avg_prev_30d_amount
    FROM daily_by_customer AS d
),
thresholded AS (
    SELECT
        *
    FROM daily_with_history
    WHERE avg_prev_30d_amount IS NOT NULL
      AND avg_prev_30d_amount > 0
      AND day_amount >= 3 * avg_prev_30d_amount
      AND (staff_count > 1 OR store_count > 1)
)
SELECT
    t.customer_id,
    cus.h03 AS customer_first_name,
    cus.h04 AS customer_last_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    t.activity_date,
    t.day_amount,
    t.payment_count,
    t.staff_count,
    ROUND(t.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    RANK() OVER (
        ORDER BY (t.day_amount / t.avg_prev_30d_amount) DESC
    ) AS suspicious_rank_overall
FROM thresholded AS t
JOIN cus
    ON cus.h01 = t.customer_id
JOIN adr
    ON adr.e01 = cus.h06
JOIN cty
    ON cty.d01 = adr.e05
JOIN cnt
    ON cnt.c01 = cty.d03
ORDER BY
    (t.day_amount / t.avg_prev_30d_amount) DESC,
    t.day_amount DESC,
    t.customer_id,
    t.activity_date;