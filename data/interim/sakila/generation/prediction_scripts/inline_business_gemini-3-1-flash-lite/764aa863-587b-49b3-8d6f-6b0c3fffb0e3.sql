WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_payments
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_categories AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(DISTINCT flc.l02) AS category_count
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc ON flc.l01 = i.n02
    GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_stats AS (
    SELECT
        mp.*,
        mc.category_count,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_avg
    FROM monthly_payments AS mp
    JOIN monthly_categories AS mc ON mc.customer_id = mp.customer_id AND mc.month_start = mp.month_start
),
ranked_stats AS (
    SELECT
        cs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country,
        RANK() OVER (
            PARTITION BY cn.c01, cs.month_start
            ORDER BY cs.total_amount DESC
        ) AS country_rank
    FROM customer_stats AS cs
    JOIN cus AS c ON c.h01 = cs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    WHERE cs.prev_3_months_avg IS NOT NULL
      AND cs.total_amount > 3 * cs.prev_3_months_avg
      AND cs.staff_count >= 2
      AND cs.category_count >= 3
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    customer_name,
    country,
    city,
    total_amount,
    payment_count,
    max_payment,
    ROUND(CAST(foreign_store_payments AS REAL) / payment_count, 4) AS foreign_store_share,
    country_rank
FROM ranked_stats
ORDER BY month_start, country_rank;