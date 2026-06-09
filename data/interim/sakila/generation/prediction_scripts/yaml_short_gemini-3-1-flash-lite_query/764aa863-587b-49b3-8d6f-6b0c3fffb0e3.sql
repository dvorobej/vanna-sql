WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        COUNT(DISTINCT fc.l02) AS category_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_payments
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_stats AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg,
        COUNT(*) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_payments AS mp
),
filtered_clients AS (
    SELECT
        ms.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id
    FROM monthly_stats AS ms
    JOIN cus AS c ON c.h01 = ms.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE ms.prev_months_count = 3
      AND ms.total_amount > 3 * ms.prev_3_month_avg
      AND ms.staff_count >= 2
      AND ms.category_count >= 3
),
ranked_clients AS (
    SELECT
        fc.*,
        RANK() OVER (
            PARTITION BY fc.country_id, fc.month_start
            ORDER BY fc.total_amount DESC
        ) AS country_rank
    FROM filtered_clients AS fc
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    country,
    city,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(CAST(foreign_store_payments AS REAL) / payment_count, 4) AS foreign_store_share,
    country_rank
FROM ranked_clients
ORDER BY month, country, country_rank;