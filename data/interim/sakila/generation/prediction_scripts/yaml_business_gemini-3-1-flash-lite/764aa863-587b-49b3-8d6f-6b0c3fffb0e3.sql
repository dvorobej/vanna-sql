WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        COUNT(DISTINCT flc.l02) AS category_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS foreign_store_share
    FROM pay AS p
    JOIN ren AS r ON p.p04 = r.q01
    JOIN inv AS i ON r.q03 = i.n01
    JOIN flc ON i.n02 = flc.l01
    JOIN cus AS c ON p.p02 = c.h01
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months
    FROM monthly_payments AS mp
),
filtered_customers AS (
    SELECT
        mwh.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id
    FROM monthly_with_history AS mwh
    JOIN cus AS c ON mwh.customer_id = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    WHERE mwh.total_amount > 3 * mwh.avg_prev_3_months
      AND mwh.staff_count >= 2
      AND mwh.category_count >= 3
)
SELECT
    fc.month_start,
    fc.customer_name,
    fc.country,
    fc.city,
    fc.total_amount,
    fc.payment_count,
    fc.max_payment,
    fc.foreign_store_share,
    RANK() OVER (
        PARTITION BY fc.country_id, fc.month_start
        ORDER BY fc.total_amount DESC
    ) AS country_rank
FROM filtered_customers AS fc
ORDER BY fc.month_start, fc.country, country_rank;