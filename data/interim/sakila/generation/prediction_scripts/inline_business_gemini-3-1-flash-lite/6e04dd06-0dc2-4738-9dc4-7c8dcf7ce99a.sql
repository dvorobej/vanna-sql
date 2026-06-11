WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS monthly_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        GROUP_CONCAT(DISTINCT c.h02) AS store_ids
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    GROUP BY 1, 2
),
history_stats AS (
    SELECT
        ms.*,
        c.h06 AS address_id,
        cty.d03 AS country_id,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months
    FROM monthly_stats ms
    JOIN cus c ON ms.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
),
country_stats AS (
    SELECT
        payment_month,
        country_id,
        monthly_sum,
        PERCENT_RANK() OVER (PARTITION BY payment_month, country_id ORDER BY monthly_sum) AS p_rank,
        AVG(monthly_sum) OVER (PARTITION BY payment_month, country_id) AS median_country_sum
    FROM history_stats
),
top_clients AS (
    SELECT payment_month, country_id, customer_id
    FROM (
        SELECT hs.payment_month, hs.customer_id, cty.d03 AS country_id,
               PERCENT_RANK() OVER (PARTITION BY hs.payment_month, cty.d03 ORDER BY hs.monthly_sum) as p_rank
        FROM history_stats hs
        JOIN cus c ON hs.customer_id = c.h01
        JOIN adr a ON c.h06 = a.e01
        JOIN cty ON a.e05 = cty.d01
    )
    WHERE p_rank >= 0.95
)
SELECT
    hs.customer_id,
    hs.payment_month,
    hs.monthly_sum,
    hs.monthly_count,
    hs.staff_ids,
    hs.store_ids,
    hs.avg_prev_3_months,
    cs.median_country_sum
FROM history_stats hs
JOIN country_stats cs ON hs.payment_month = cs.payment_month AND hs.country_id = cs.country_id AND hs.monthly_sum = cs.monthly_sum
JOIN top_clients tc ON hs.customer_id = tc.customer_id AND hs.payment_month = tc.payment_month
WHERE hs.monthly_sum >= 3 * COALESCE(hs.avg_prev_3_months, 0)
  AND hs.monthly_sum >= 2 * cs.median_country_sum
ORDER BY hs.monthly_sum DESC;