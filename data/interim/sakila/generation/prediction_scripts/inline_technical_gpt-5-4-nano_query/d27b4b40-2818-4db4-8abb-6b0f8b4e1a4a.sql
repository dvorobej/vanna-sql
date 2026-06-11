WITH payment_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_total_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(r_store.j01, p.p03)) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    LEFT JOIN sto AS r_store
        ON r_store.j01 = i.n03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_prev_avg AS (
    SELECT
        pd.*,
        (
            SELECT AVG(dp2.day_total_amount)
            FROM payment_daily AS dp2
            WHERE dp2.customer_id = pd.customer_id
              AND dp2.payment_date >= date(pd.payment_date, '-30 days')
              AND dp2.payment_date < pd.payment_date
        ) AS avg_daily_amount_prev_30_days
    FROM payment_daily AS pd
),
suspicious_days AS (
    SELECT
        d.*,
        (d.day_total_amount / NULLIF(d.avg_daily_amount_prev_30_days, 0)) AS exceed_ratio
    FROM daily_with_prev_avg AS d
    WHERE d.avg_daily_amount_prev_30_days IS NOT NULL
      AND d.avg_daily_amount_prev_30_days > 0
      AND d.day_total_amount >= 3 * d.avg_daily_amount_prev_30_days
      AND d.payment_count >= 3
      AND (d.staff_count >= 2 OR d.store_count >= 2)
),
ranked_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.day_total_amount DESC
        ) AS day_rank_by_amount
    FROM suspicious_days AS sd
)
SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_full_name,
    co.c02 AS country_name,
    ct.d02 AS city_name,
    rd.payment_date,
    rd.payment_count,
    ROUND(rd.day_total_amount, 2) AS day_total_amount,
    ROUND(rd.avg_daily_amount_prev_30_days, 2) AS avg_daily_amount_prev_30_days,
    ROUND(rd.exceed_ratio, 4) AS exceed_ratio,
    rd.day_rank_by_amount
FROM ranked_days AS rd
JOIN cus AS c
    ON c.h01 = rd.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty AS ct
    ON ct.d01 = a.e05
JOIN cnt AS co
    ON co.c01 = ct.d03
ORDER BY
    rd.customer_id,
    rd.day_rank_by_amount,
    rd.payment_date;