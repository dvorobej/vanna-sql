WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id
            ORDER BY mcs.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_amount
    FROM monthly_customer_stats AS mcs
),
country_median_counts AS (
    SELECT
        c.country_id,
        mcs.payment_month,
        AVG(mcs.payment_count) AS median_payment_count
    FROM monthly_customer_stats AS mcs
    JOIN (
        SELECT h01 AS customer_id, c01 AS country_id
        FROM cus
        JOIN adr ON adr.e01 = cus.h06
        JOIN cty ON cty.d01 = adr.e05
        JOIN cnt ON cnt.c01 = cty.d03
    ) AS c ON c.customer_id = mcs.customer_id
    GROUP BY c.country_id, mcs.payment_month
),
category_share AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) * 1.0 / SUM(p.p05) AS action_new_share
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
suspicious_cases AS (
    SELECT
        ch.*,
        c.country_name,
        c.city_name,
        c.store_id,
        cs.action_new_share
    FROM customer_history AS ch
    JOIN (
        SELECT cus.h01 AS customer_id, cnt.c02 AS country_name, cty.d02 AS city_name, cus.h02 AS store_id, cnt.c01 AS country_id
        FROM cus
        JOIN adr ON adr.e01 = cus.h06
        JOIN cty ON cty.d01 = adr.e05
        JOIN cnt ON cnt.c01 = cty.d03
    ) AS c ON c.customer_id = ch.customer_id
    JOIN country_median_counts AS cmc ON cmc.country_id = c.country_id AND cmc.payment_month = ch.payment_month
    LEFT JOIN category_share AS cs ON cs.customer_id = ch.customer_id AND cs.payment_month = ch.payment_month
    WHERE ch.avg_prev_amount > 0
      AND ch.monthly_amount > 3 * ch.avg_prev_amount
      AND ch.payment_count > cmc.median_payment_count
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_name ORDER BY monthly_amount DESC) AS country_rank
    FROM suspicious_cases
)
SELECT
    payment_month,
    customer_id,
    country_name,
    city_name,
    store_id,
    payment_count,
    ROUND(monthly_amount, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(COALESCE(action_new_share, 0), 4) AS action_new_share,
    country_rank
FROM ranked_suspicious
ORDER BY country_name, country_rank;