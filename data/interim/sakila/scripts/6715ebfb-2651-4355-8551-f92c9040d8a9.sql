WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country,
        ci.d01 AS city_id,
        ci.d02 AS city,
        strftime('%Y-%m', p.p06) AS payment_month,
        CAST(p.p05 AS REAL) AS payment_amount,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM ren r
                JOIN inv i ON i.n01 = r.q03
                JOIN flc fc ON fc.l01 = i.n02
                JOIN cat ca ON ca.g01 = fc.l02
                WHERE r.q01 = p.p04
                  AND ca.g02 IN ('Action', 'New')
            )
            THEN 1
            ELSE 0
        END AS is_action_or_new
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
monthly_customer AS (
    SELECT
        customer_id,
        customer_first_name,
        customer_last_name,
        store_id,
        country_id,
        country,
        city_id,
        city,
        payment_month,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS payment_sum,
        MAX(payment_amount) AS max_payment,
        SUM(is_action_or_new) AS action_or_new_payment_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        customer_first_name,
        customer_last_name,
        store_id,
        country_id,
        country,
        city_id,
        city,
        payment_month
),
monthly_with_history AS (
    SELECT
        mc.*,
        AVG(payment_sum) OVER (
            PARTITION BY customer_id
            ORDER BY payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_payment_sum,
        AVG(payment_count) OVER (
            PARTITION BY customer_id
            ORDER BY payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_payment_count
    FROM monthly_customer mc
),
country_month_counts AS (
    SELECT
        country_id,
        payment_month,
        payment_count,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, payment_month
            ORDER BY payment_count
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY country_id, payment_month
        ) AS cnt
    FROM monthly_customer
),
country_month_median AS (
    SELECT
        country_id,
        payment_month,
        AVG(payment_count * 1.0) AS median_country_payment_count
    FROM country_month_counts
    WHERE rn IN (
        CAST((cnt + 1) / 2 AS INTEGER),
        CAST((cnt + 2) / 2 AS INTEGER)
    )
    GROUP BY country_id, payment_month
),
suspicious_months AS (
    SELECT
        mwh.*
    FROM monthly_with_history mwh
    JOIN country_month_median cmm
      ON cmm.country_id = mwh.country_id
     AND cmm.payment_month = mwh.payment_month
    WHERE mwh.prev_avg_payment_sum IS NOT NULL
      AND mwh.payment_sum > 3.0 * mwh.prev_avg_payment_sum
      AND mwh.payment_count > cmm.median_country_payment_count
),
suspicious_clients AS (
    SELECT
        customer_id,
        customer_first_name,
        customer_last_name,
        country_id,
        country,
        city_id,
        city,
        store_id,
        COUNT(*) AS suspicious_month_count,
        SUM(payment_count) AS payment_count,
        ROUND(SUM(payment_sum), 2) AS total_amount,
        ROUND(MAX(max_payment), 2) AS max_single_payment,
        ROUND(
            SUM(action_or_new_payment_count) * 1.0 / NULLIF(SUM(payment_count), 0),
            4
        ) AS action_new_payment_share
    FROM suspicious_months
    GROUP BY
        customer_id,
        customer_first_name,
        customer_last_name,
        country_id,
        country,
        city_id,
        city,
        store_id
)
SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    country,
    city,
    store_id,
    suspicious_month_count,
    payment_count,
    total_amount,
    max_single_payment,
    action_new_payment_share,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY total_amount DESC
    ) AS country_suspicious_amount_rank
FROM suspicious_clients
ORDER BY
    country,
    country_suspicious_amount_rank,
    customer_id;