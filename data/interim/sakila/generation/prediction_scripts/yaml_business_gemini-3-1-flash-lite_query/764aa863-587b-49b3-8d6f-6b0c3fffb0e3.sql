WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT fc.l02) AS category_count,
        SUM(CASE WHEN stf.o07 <> cus.h02 THEN 1 ELSE 0 END) AS off_home_store_count
    FROM pay AS p
    JOIN cus AS cus ON cus.h01 = p.p02
    JOIN stf AS stf ON stf.o01 = p.p03
    JOIN ren AS ren ON ren.q01 = p.p04
    JOIN inv AS inv ON inv.n01 = ren.q03
    JOIN flc AS fc ON fc.l01 = inv.n02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id
            ORDER BY mcs.payment_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg,
        COUNT(*) OVER (
            PARTITION BY mcs.customer_id
            ORDER BY mcs.payment_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS history_count
    FROM monthly_customer_stats AS mcs
),
ranked_by_country AS (
    SELECT
        mwh.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        RANK() OVER (
            PARTITION BY cnt.c01, mwh.payment_month
            ORDER BY mwh.monthly_amount DESC
        ) AS country_rank
    FROM monthly_with_history AS mwh
    JOIN cus AS c ON c.h01 = mwh.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    WHERE mwh.history_count = 3
      AND mwh.monthly_amount > 3 * mwh.prev_3_month_avg
      AND mwh.staff_count >= 2
      AND mwh.category_count >= 3
)
SELECT
    payment_month,
    country,
    city,
    ROUND(monthly_amount, 2) AS monthly_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(CAST(off_home_store_count AS REAL) / payment_count, 4) AS off_home_store_share,
    country_rank
FROM ranked_by_country
ORDER BY
    payment_month,
    country,
    country_rank;