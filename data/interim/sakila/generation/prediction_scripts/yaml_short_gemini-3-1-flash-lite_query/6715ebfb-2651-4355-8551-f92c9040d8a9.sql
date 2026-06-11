WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) AS action_new_amount
    FROM pay AS p
    LEFT JOIN ren AS r ON p.p04 = r.q01
    LEFT JOIN inv AS i ON r.q03 = i.n01
    LEFT JOIN flc AS fc ON i.n02 = fc.l01
    LEFT JOIN cat ON fc.l02 = cat.g01
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
    FROM monthly_customer_stats mcs
),
country_median_counts AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country_name,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mcs.payment_count) OVER (PARTITION BY cnt.c01) AS country_median_count
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    JOIN monthly_customer_stats mcs ON c.h01 = mcs.customer_id
),
suspicious_cases AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        c.h02 AS store_id,
        cmc.country_median_count,
        (ch.action_new_amount / NULLIF(ch.monthly_amount, 0)) AS action_new_share
    FROM customer_history ch
    JOIN cus c ON ch.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    JOIN country_median_counts cmc ON ch.customer_id = cmc.customer_id
    WHERE ch.hist_avg_amount > 0 
      AND ch.monthly_amount > 3 * ch.hist_avg_amount
      AND ch.payment_count > cmc.country_median_count
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country ORDER BY monthly_amount DESC) AS country_rank
    FROM suspicious_cases
)
SELECT
    country,
    city,
    store_id,
    payment_month,
    payment_count,
    ROUND(monthly_amount, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(action_new_share, 4) AS action_new_share,
    country_rank
FROM ranked_suspicious
ORDER BY country, country_rank;