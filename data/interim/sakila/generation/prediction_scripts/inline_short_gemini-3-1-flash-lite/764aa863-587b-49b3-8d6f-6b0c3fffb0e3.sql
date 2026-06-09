WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS foreign_store_share
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
combined_stats AS (
    SELECT
        mcs.*,
        mc.category_count,
        AVG(mcs.total_amount) OVER (
            PARTITION BY mcs.customer_id
            ORDER BY mcs.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_avg
    FROM monthly_customer_stats AS mcs
    JOIN monthly_categories AS mc ON mc.customer_id = mcs.customer_id AND mc.month_start = mcs.month_start
),
filtered_stats AS (
    SELECT
        cs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        RANK() OVER (PARTITION BY cnt.c01, cs.month_start ORDER BY cs.total_amount DESC) AS country_rank
    FROM combined_stats AS cs
    JOIN cus AS c ON c.h01 = cs.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE cs.prev_3_months_avg IS NOT NULL
      AND cs.total_amount > 3 * cs.prev_3_months_avg
      AND cs.staff_count >= 2
      AND cs.category_count >= 3
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    country,
    city,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(foreign_store_share, 4) AS foreign_store_share,
    country_rank
FROM filtered_stats
ORDER BY month_start, country, country_rank;