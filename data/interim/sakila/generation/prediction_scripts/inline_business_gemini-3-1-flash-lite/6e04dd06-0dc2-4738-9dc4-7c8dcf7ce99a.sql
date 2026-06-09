WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS monthly_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        GROUP_CONCAT(DISTINCT s.o07) AS store_ids
    FROM pay p
    JOIN stf s ON p.p03 = s.o01
    GROUP BY 1, 2
),
customer_geo AS (
    SELECT c.h01 AS customer_id, cnt.c01 AS country_id
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt ON ci.d03 = cnt.c01
),
enriched_stats AS (
    SELECT
        ms.*,
        cg.country_id,
        AVG(ms.monthly_sum) OVER (PARTITION BY ms.customer_id ORDER BY ms.payment_month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS hist_avg_sum,
        PERCENT_RANK() OVER (PARTITION BY ms.country_id, ms.payment_month ORDER BY ms.monthly_sum DESC) AS country_percentile,
        (SELECT AVG(m2.monthly_sum) FROM monthly_stats m2 
         JOIN customer_geo cg2 ON m2.customer_id = cg2.customer_id 
         WHERE cg2.country_id = cg.country_id AND m2.payment_month = ms.payment_month) AS country_median_sum
    FROM monthly_stats ms
    JOIN customer_geo cg ON ms.customer_id = cg.customer_id
)
SELECT 
    customer_id, 
    payment_month, 
    monthly_sum, 
    monthly_count, 
    staff_ids, 
    store_ids
FROM enriched_stats
WHERE monthly_sum >= 3 * COALESCE(hist_avg_sum, 0)
  AND monthly_sum >= 2 * country_median_sum
  AND country_percentile <= 0.05
ORDER BY payment_month DESC, monthly_sum DESC;