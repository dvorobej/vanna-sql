WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT CASE WHEN stf.o07 <> cus.h02 THEN p.p01 END) * 1.0 / COUNT(*) AS foreign_store_share,
        COUNT(DISTINCT flc.l02) AS category_count
    FROM pay AS p
    JOIN cus ON cus.h01 = p.p02
    JOIN stf ON stf.o01 = p.p03
    JOIN ren ON ren.q01 = p.p04
    JOIN inv ON inv.n01 = ren.q03
    JOIN flc ON flc.l01 = inv.n02
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
ranked_monthly AS (
    SELECT
        mwh.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        RANK() OVER (
            PARTITION BY cnt.c01, mwh.month_start
            ORDER BY mwh.total_amount DESC
        ) AS country_rank
    FROM monthly_with_history AS mwh
    JOIN cus AS c ON c.h01 = mwh.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE mwh.staff_count >= 2
      AND mwh.category_count >= 3
      AND mwh.total_amount > 3 * mwh.avg_prev_3_months
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    customer_name,
    country,
    city,
    total_amount,
    payment_count,
    max_payment,
    ROUND(foreign_store_share, 4) AS foreign_store_share,
    country_rank
FROM ranked_monthly
ORDER BY month_start, country, country_rank;