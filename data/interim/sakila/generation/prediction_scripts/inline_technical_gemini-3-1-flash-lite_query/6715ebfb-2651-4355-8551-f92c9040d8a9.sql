WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS action_new_share
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN flc AS fc ON fc.l01 = i.n02
    LEFT JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS hist_avg_amount
    FROM monthly_customer_stats AS mcs
),
country_median_counts AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        c.h02 AS store_id,
        (SELECT AVG(m.payment_count) 
         FROM (SELECT payment_count FROM monthly_customer_stats AS mcs2 
               JOIN cus AS c2 ON c2.h01 = mcs2.customer_id
               JOIN adr AS a2 ON a2.e01 = c2.h06
               JOIN cty AS ct2 ON ct2.d01 = a2.e05
               WHERE ct2.d03 = cnt.c01) AS m) AS country_median_count
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
suspicious_cases AS (
    SELECT
        ch.*,
        cmc.country_name,
        cmc.city_name,
        cmc.store_id,
        cmc.country_id
    FROM customer_history AS ch
    JOIN country_median_counts AS cmc ON cmc.customer_id = ch.customer_id
    WHERE ch.hist_avg_amount > 0
      AND ch.monthly_amount > 3 * ch.hist_avg_amount
      AND ch.payment_count > cmc.country_median_count
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_id ORDER BY monthly_amount DESC) AS country_rank
    FROM suspicious_cases
)
SELECT
    country_name,
    city_name,
    store_id,
    payment_month,
    payment_count,
    ROUND(monthly_amount, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(action_new_share, 4) AS action_new_share,
    country_rank
FROM ranked_suspicious
ORDER BY country_name, country_rank;