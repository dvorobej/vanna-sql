WITH
customer_base AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS month_amount,
        MAX(CAST(p.p05 AS REAL)) AS max_single_payment
    FROM pay AS p
    WHERE p.p04 IS NOT NULL
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
monthly_enriched AS (
    SELECT
        cb.customer_id,
        cb.store_id,
        cb.country_id,
        cb.country_name,
        cb.city_name,
        mp.month_start,
        mp.payment_count,
        mp.month_amount,
        mp.max_single_payment,
        AVG(mp.month_amount) OVER (
            PARTITION BY cb.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_avg_amount_prev,
        COUNT(*) OVER (
            PARTITION BY cb.country_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_prev_months_cnt
    FROM monthly_payments AS mp
    JOIN customer_base AS cb
        ON cb.customer_id = mp.customer_id
),
country_month_counts AS (
    SELECT
        me.country_id,
        me.month_start,
        me.payment_count,
        me.customer_id,
        DENSE_RANK() OVER (
            PARTITION BY me.country_id, me.month_start
            ORDER BY me.payment_count
        ) AS pay_count_rank_asc,
        COUNT(*) OVER (
            PARTITION BY me.country_id, me.month_start
        ) AS country_customers_cnt
    FROM monthly_enriched AS me
),
country_month_median_counts AS (
    SELECT
        country_id,
        month_start,
        AVG(CAST(payment_count AS REAL)) AS median_payment_count
    FROM (
        SELECT
            cmc.*,
            ROW_NUMBER() OVER (
                PARTITION BY cmc.country_id, cmc.month_start
                ORDER BY cmc.payment_count
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY cmc.country_id, cmc.month_start
            ) AS cnt
        FROM country_month_counts AS cmc
    ) t
    WHERE rn IN (
        CAST((cnt + 1) / 2 AS INTEGER),
        CAST((cnt + 2) / 2 AS INTEGER)
    )
    GROUP BY
        country_id,
        month_start
),
suspicious_months AS (
    SELECT
        me.*,
        cmmed.median_payment_count,
        (CASE
            WHEN me.personal_avg_amount_prev > 0 THEN me.month_amount / me.personal_avg_amount_prev
        END) AS ratio_to_personal_avg
    FROM monthly_enriched AS me
    JOIN country_month_median_counts AS cmmed
        ON cmmed.country_id = me.country_id
       AND cmmed.month_start = me.month_start
    WHERE me.personal_prev_months_cnt > 0
      AND me.personal_avg_amount_prev > 0
      AND me.month_amount > 3.0 * me.personal_avg_amount_prev
      AND me.payment_count > cmmed.median_payment_count
),
action_new_shares AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_rental_payments_amount,
        SUM(CASE
            WHEN cat.g02 IN ('Action', 'New') THEN p.p05
            ELSE 0
        END) AS action_new_rental_payments_amount
    FROM pay AS p
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flc AS fc
        ON fc.l01 = i.n02
    JOIN cat
        ON cat.g01 = fc.l02
    WHERE p.p04 IS NOT NULL
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
country_suspicious_rank AS (
    SELECT
        sm.*,
        DENSE_RANK() OVER (
            PARTITION BY sm.country_id
            ORDER BY sm.month_amount DESC
        ) AS country_customer_suspicious_rank
    FROM suspicious_months AS sm
)
SELECT
    csr.country_name AS country,
    csr.city_name AS city,
    csr.store_id AS store_id,
    csr.payment_count,
    ROUND(csr.month_amount, 2) AS total_suspicious_payments_amount,
    ROUND(csr.max_single_payment, 2) AS max_single_payment,
    ROUND(
        (CASE
            WHEN COALESCE(an.total_rental_payments_amount, 0) = 0 THEN 0
            ELSE COALESCE(an.action_new_rental_payments_amount, 0) / an.total_rental_payments_amount
        END),
        4
    ) AS action_new_rentals_share,
    csr.country_customer_suspicious_rank AS suspicious_customer_rank_in_country
FROM country_suspicious_rank AS csr
LEFT JOIN action_new_shares AS an
    ON an.customer_id = csr.customer_id
   AND an.month_start = csr.month_start
ORDER BY
    csr.country_id,
    csr.country_customer_suspicious_rank,
    csr.month_amount DESC,
    csr.customer_id;