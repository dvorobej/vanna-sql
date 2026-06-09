WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_payments AS mp
),
filtered_months AS (
    SELECT
        mwh.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        ct.d02 AS city,
        cnt.c01 AS country_id,
        (mwh.total_amount - mwh.prev_avg_amount) AS deviation
    FROM monthly_with_history AS mwh
    JOIN cus AS c ON c.h01 = mwh.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = ct.d03
    WHERE mwh.prev_avg_amount IS NOT NULL
      AND mwh.total_amount >= mwh.prev_avg_amount * 2
      AND mwh.payment_count >= 5
      AND (mwh.staff_count > 1 OR mwh.store_count > 1)
),
customer_monthly_counts AS (
    SELECT customer_id, COUNT(*) AS months_count
    FROM filtered_months
    GROUP BY customer_id
),
ranked_deviations AS (
    SELECT
        fm.*,
        RANK() OVER (
            PARTITION BY fm.country_id, fm.payment_month
            ORDER BY fm.deviation DESC
        ) AS country_rank
    FROM filtered_months AS fm
    JOIN customer_monthly_counts AS cmc ON cmc.customer_id = fm.customer_id
    WHERE cmc.months_count = 12
)
SELECT
    payment_month,
    country,
    city,
    total_amount,
    payment_count,
    ROUND(deviation, 2) AS deviation,
    country_rank
FROM ranked_deviations
ORDER BY payment_month, country, country_rank;