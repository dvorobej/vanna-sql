WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS action_new_share
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        customer_id,
        AVG(monthly_amount) AS avg_monthly_amount
    FROM monthly_customer_stats
    GROUP BY customer_id
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        ct.d02 AS city_name,
        c.h02 AS store_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mcs.payment_count) OVER (PARTITION BY cnt.c01, mcs.payment_month) AS country_median_payment_count
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
),
suspicious_cases AS (
    SELECT
        mcs.*,
        ch.avg_monthly_amount,
        cs.country_name,
        cs.city_name,
        cs.store_id,
        cs.country_median_payment_count
    FROM monthly_customer_stats mcs
    JOIN customer_history ch ON ch.customer_id = mcs.customer_id
    JOIN country_stats cs ON cs.customer_id = mcs.customer_id
    WHERE mcs.monthly_amount > ch.avg_monthly_amount * 2
      AND mcs.payment_count > cs.country_median_payment_count
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_name ORDER BY monthly_amount DESC) AS country_risk_rank
    FROM suspicious_cases
)
SELECT
    payment_month,
    customer_id,
    country_name,
    city_name,
    store_id,
    payment_count,
    ROUND(monthly_amount, 2) AS monthly_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(action_new_share, 4) AS action_new_share,
    country_risk_rank
FROM ranked_suspicious
ORDER BY country_name, country_risk_rank;