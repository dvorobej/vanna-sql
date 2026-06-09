WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        DATE(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        ci.d02 AS customer_city,
        cnt.c02 AS customer_country,
        CASE WHEN p.p04 IS NULL THEN 0 ELSE 1 END AS has_rental
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
    JOIN stf s ON s.o01 = p.p03
),
monthly_customer AS (
    SELECT
        customer_id,
        customer_country,
        customer_city,
        month_start,
        COUNT(*) AS payment_count,
        SUM(amount) AS month_total_amount,
        MAX(amount) AS max_payment_amount,
        SUM(amount) AS month_sum_for_share_base,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT staff_store_id) AS distinct_store_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        customer_country,
        customer_city,
        month_start
),
monthly_with_baseline AS (
    SELECT
        mc.*,
        AVG(month_total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_month_total_amount
    FROM monthly_customer mc
),
suspicious_months AS (
    SELECT
        mwb.*,
        (mwb.max_payment_amount / NULLIF(mwb.month_total_amount, 0)) AS max_payment_share,
        RANK() OVER (
            PARTITION BY customer_country, month_start
            ORDER BY mwb.month_total_amount DESC
        ) AS customer_month_rank_in_country
    FROM monthly_with_baseline mwb
    WHERE mwb.prev_avg_month_total_amount IS NOT NULL
      AND mwb.prev_avg_month_total_amount > 0
      AND mwb.month_total_amount >= 3.0 * mwb.prev_avg_month_total_amount
      AND mwb.payment_count >= 3
      AND mwb.distinct_staff_count >= 2
      AND mwb.distinct_store_count >= 2
)
SELECT
    c.h03 AS first_name,
    c.h04 AS last_name,
    sm.customer_country AS country,
    sm.customer_city AS city,
    sm.month_start AS month_start_date,
    sm.payment_count,
    ROUND(sm.month_total_amount, 2) AS month_total_amount,
    ROUND(sm.max_payment_amount, 2) AS max_payment_amount,
    ROUND(sm.max_payment_share, 4) AS max_payment_share_in_month,
    sm.distinct_staff_count AS distinct_staff_count,
    sm.distinct_store_count AS distinct_store_count,
    sm.customer_month_rank_in_country AS customer_month_rank_in_country
FROM suspicious_months sm
JOIN cus c ON c.h01 = sm.customer_id
ORDER BY
    sm.customer_country,
    sm.month_start,
    sm.customer_month_rank_in_country,
    c.h04,
    c.h03;