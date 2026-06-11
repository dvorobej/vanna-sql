WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > r.q02 + (flm.i07 || ' days') THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS late_return_share
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flm AS flm ON flm.i01 = i.n02
    GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        co.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
monthly_data AS (
    SELECT
        mcs.*,
        cg.store_id,
        cg.country,
        cg.city,
        AVG(mcs.total_amount) OVER (PARTITION BY mcs.customer_id ORDER BY mcs.month_start ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS avg_prev_amount
    FROM monthly_customer_stats AS mcs
    JOIN customer_geo AS cg ON cg.customer_id = mcs.customer_id
),
percentiles AS (
    SELECT
        month_start,
        store_id,
        country,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_amount) OVER (PARTITION BY month_start, store_id, country) AS p95_amount
    FROM monthly_data
)
SELECT
    md.country,
    md.city,
    md.store_id,
    strftime('%Y-%m', md.month_start) AS payment_month,
    ROUND(md.total_amount, 2) AS total_amount,
    md.payment_count,
    md.staff_count,
    ROUND(md.late_return_share, 4) AS late_return_share,
    RANK() OVER (PARTITION BY md.month_start, md.country ORDER BY md.total_amount DESC) AS country_rank
FROM monthly_data AS md
JOIN percentiles AS p ON md.month_start = p.month_start AND md.store_id = p.store_id AND md.country = p.country
WHERE md.avg_prev_amount > 0
  AND md.total_amount > 3 * md.avg_prev_amount
  AND md.total_amount > p.p95_amount
ORDER BY md.month_start DESC, country_rank ASC;