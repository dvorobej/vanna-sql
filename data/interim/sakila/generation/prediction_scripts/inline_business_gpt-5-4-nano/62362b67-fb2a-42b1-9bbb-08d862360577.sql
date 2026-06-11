WITH daily_totals AS (
    SELECT
        c.h01 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS daily_amount
    FROM cus AS c
    JOIN pay AS p
        ON p.p02 = c.h01
    GROUP BY
        c.h01,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        dt.customer_id,
        dt.payment_date,
        dt.payment_count,
        dt.daily_amount,
        (
            SELECT AVG(dh.daily_amount)
            FROM daily_totals AS dh
            WHERE dh.customer_id = dt.customer_id
              AND dh.payment_date >= date(dt.payment_date, '-30 days')
              AND dh.payment_date < dt.payment_date
        ) AS avg_prev_30d_amount
    FROM daily_totals AS dt
),
staff_store_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS customer_country,
    ct.d02 AS customer_city,
    dwh.payment_date,
    dwh.payment_count,
    ROUND(dwh.daily_amount, 2) AS daily_amount,
    ROUND(dwh.avg_prev_30d_amount, 2) AS avg_daily_amount_prev_30d,
    ROUND(dwh.daily_amount / NULLIF(dwh.avg_prev_30d_amount, 0), 2) AS exceed_ratio,
    ssd.distinct_staff_count,
    ssd.distinct_store_count,
    RANK() OVER (
        PARTITION BY cnt.c02
        ORDER BY (dwh.daily_amount - dwh.avg_prev_30d_amount) DESC
    ) AS suspicion_rank_in_country
FROM daily_with_history AS dwh
JOIN cus AS c
    ON c.h01 = dwh.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty AS ct
    ON ct.d01 = a.e05
JOIN cnt
    ON cnt.c01 = ct.d03
JOIN staff_store_daily AS ssd
    ON ssd.customer_id = dwh.customer_id
   AND ssd.payment_date = dwh.payment_date
WHERE dwh.avg_prev_30d_amount IS NOT NULL
  AND dwh.avg_prev_30d_amount > 0
  AND dwh.daily_amount >= 3.0 * dwh.avg_prev_30d_amount
  AND (ssd.distinct_staff_count >= 2 OR ssd.distinct_store_count >= 2)
ORDER BY
    customer_country,
    suspicion_rank_in_country,
    dwh.daily_amount DESC,
    dwh.payment_date,
    dwh.customer_id;