WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        ms.*,
        AVG(ms.total_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_stats AS ms
    WHERE ms.payment_count >= 5 
      AND (ms.staff_count >= 2 OR ms.store_count >= 2)
),
filtered_months AS (
    SELECT
        mwh.*,
        (mwh.total_amount / NULLIF(mwh.prev_avg_amount, 0)) AS deviation_ratio
    FROM monthly_with_history AS mwh
    WHERE mwh.prev_avg_amount IS NOT NULL 
      AND mwh.total_amount >= 2 * mwh.prev_avg_amount
),
final_report AS (
    SELECT
        fm.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        ct.d02 AS city,
        cnt.c01 AS country_id,
        RANK() OVER (
            PARTITION BY cnt.c01, fm.payment_month 
            ORDER BY fm.deviation_ratio DESC
        ) AS country_deviation_rank
    FROM filtered_months AS fm
    JOIN cus AS c ON c.h01 = fm.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    total_amount,
    payment_count,
    ROUND(deviation_ratio, 2) AS deviation_ratio,
    country_deviation_rank
FROM final_report
ORDER BY payment_month, country, country_deviation_rank;