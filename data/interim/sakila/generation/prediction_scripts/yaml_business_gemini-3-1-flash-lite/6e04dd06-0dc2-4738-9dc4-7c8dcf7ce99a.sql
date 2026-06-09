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
customer_history AS (
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
        country_id,
        payment_month,
        monthly_sum,
        PERCENT_RANK() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_sum) as p_rank,
        (SELECT AVG(monthly_sum) FROM monthly_stats ms2 
         JOIN cus c2 ON ms2.customer_id = c2.h01 
         JOIN adr a2 ON c2.h06 = a2.e01 
         WHERE a2.e05 IN (SELECT d01 FROM cty WHERE d03 = cty.d03) 
         AND ms2.payment_month = ms.payment_month) as median_country_sum
    FROM customer_history ms
    JOIN cty ON ms.address_id = cty.d01
)
SELECT
    ch.customer_id,
    ch.payment_month,
    ch.monthly_sum,
    ch.monthly_count,
    ch.staff_ids,
    ch.store_ids
FROM customer_history ch
JOIN country_stats cs ON ch.customer_id = cs.customer_id AND ch.payment_month = cs.payment_month
WHERE ch.monthly_sum >= 3 * ch.avg_prev_3_months
  AND ch.monthly_sum >= 2 * cs.median_country_sum
  AND cs.p_rank >= 0.95
ORDER BY ch.monthly_sum DESC;