WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
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
    FROM monthly_stats AS ms
),
filtered_months AS (
    SELECT
        hs.*,
        (hs.monthly_sum - hs.prev_avg_sum) AS deviation
    FROM history_stats AS hs
    WHERE hs.prev_avg_sum IS NOT NULL
      AND hs.monthly_sum >= 2 * hs.prev_avg_sum
      AND hs.payment_count >= 5
      AND (hs.staff_count > 1 OR hs.store_count > 1)
),
customer_months_count AS (
    SELECT customer_id, COUNT(*) AS months_with_activity
    FROM filtered_months
    GROUP BY customer_id
),
final_report AS (
    SELECT
        fm.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        RANK() OVER (
            PARTITION BY cnt.c01, fm.payment_month
            ORDER BY fm.deviation DESC
        ) AS country_rank
    FROM filtered_months AS fm
    JOIN customer_months_count AS cmc ON fm.customer_id = cmc.customer_id
    JOIN cus AS c ON c.h01 = fm.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE cmc.months_with_activity = 12
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    ROUND(monthly_sum, 2) AS monthly_sum,
    payment_count,
    ROUND(deviation, 2) AS deviation_from_prev_avg,
    country_rank
FROM final_report
ORDER BY payment_month, country, country_rank;