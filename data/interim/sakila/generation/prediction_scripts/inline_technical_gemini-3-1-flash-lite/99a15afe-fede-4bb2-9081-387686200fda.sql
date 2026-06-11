WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > r.q02 THEN 1 ELSE 0 END) AS late_returns,
        COUNT(r.q01) AS total_rentals
    FROM pay p
    LEFT JOIN ren r ON p.p04 = r.q01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_stats ms
),
store_country_stats AS (
    SELECT
        ms.payment_month,
        c.h02 AS store_id,
        cnt.c01 AS country_id,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ms.monthly_sum) OVER (
            PARTITION BY ms.payment_month, c.h02, cnt.c01
        ) AS p95_sum
    FROM monthly_stats ms
    JOIN cus c ON ms.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt ON ct.d03 = cnt.c01
),
ranked_clients AS (
    SELECT
        hs.*,
        RANK() OVER (
            PARTITION BY c.h02, hs.payment_month 
            ORDER BY hs.monthly_sum DESC
        ) AS store_rank
    FROM history_stats hs
    JOIN cus c ON hs.customer_id = c.h01
)
SELECT
    c.h01, c.h03, c.h04, cnt.c02, ct.d02, c.h02 AS j01,
    rc.payment_month, rc.monthly_sum, rc.payment_count, 
    rc.staff_count,
    (CAST(rc.late_returns AS REAL) / NULLIF(rc.total_rentals, 0)) AS late_return_share,
    rc.store_rank
FROM ranked_clients rc
JOIN cus c ON rc.customer_id = c.h01
JOIN adr a ON c.h06 = a.e01
JOIN cty ct ON a.e05 = ct.d01
JOIN cnt ON ct.d03 = cnt.c01
JOIN store_country_stats scs ON rc.payment_month = scs.payment_month 
    AND c.h02 = scs.store_id AND cnt.c01 = scs.country_id
WHERE rc.prev_avg_sum IS NOT NULL
  AND rc.monthly_sum >= 3 * rc.prev_avg_sum
  AND rc.monthly_sum > scs.p95_sum;