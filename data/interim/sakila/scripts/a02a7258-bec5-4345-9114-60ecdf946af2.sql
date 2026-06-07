WITH
monthly_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        substr(p.p06, 1, 7) AS payment_month,
        SUM(p.p05) AS monthly_payment_amount,
        COUNT(*) AS monthly_payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        MAX(p.p05) AS max_payment_amount,
        MIN(p.p06) AS first_payment_date,
        MAX(p.p06) AS last_payment_date
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        co.c01,
        co.c02,
        substr(p.p06, 1, 7)
),
country_ordered AS (
    SELECT
        mp.*,
        ROW_NUMBER() OVER (
            PARTITION BY mp.country_id, mp.payment_month
            ORDER BY mp.monthly_payment_amount
        ) AS amount_row_num,
        ROW_NUMBER() OVER (
            PARTITION BY mp.country_id, mp.payment_month
            ORDER BY mp.monthly_payment_count
        ) AS count_row_num,
        COUNT(*) OVER (
            PARTITION BY mp.country_id, mp.payment_month
        ) AS country_customer_count
    FROM monthly_payments AS mp
),
country_medians AS (
    SELECT
        country_id,
        payment_month,
        AVG(
            CASE
                WHEN amount_row_num IN (
                    CAST((country_customer_count + 1) / 2 AS INTEGER),
                    CAST((country_customer_count + 2) / 2 AS INTEGER)
                )
                THEN monthly_payment_amount
            END
        ) AS country_median_payment_amount,
        AVG(
            CASE
                WHEN count_row_num IN (
                    CAST((country_customer_count + 1) / 2 AS INTEGER),
                    CAST((country_customer_count + 2) / 2 AS INTEGER)
                )
                THEN monthly_payment_count
            END
        ) AS country_median_payment_count
    FROM country_ordered
    GROUP BY
        country_id,
        payment_month
),
history_and_ranks AS (
    SELECT
        mp.*,
        AVG(mp.monthly_payment_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS customer_avg_amount_prev_months,
        AVG(mp.monthly_payment_count) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS customer_avg_count_prev_months,
        RANK() OVER (
            PARTITION BY mp.country_id, mp.payment_month
            ORDER BY mp.monthly_payment_amount DESC
        ) AS country_amount_rank,
        COUNT(*) OVER (
            PARTITION BY mp.country_id, mp.payment_month
        ) AS country_customer_month_count
    FROM monthly_payments AS mp
),
scored AS (
    SELECT
        hr.*,
        cm.country_median_payment_amount,
        cm.country_median_payment_count,
        CASE
            WHEN (
                CAST(hr.country_customer_month_count * 0.05 AS INTEGER)
                + CASE
                    WHEN hr.country_customer_month_count * 0.05 > CAST(hr.country_customer_month_count * 0.05 AS INTEGER)
                    THEN 1
                    ELSE 0
                  END
            ) < 1
            THEN 1
            ELSE (
                CAST(hr.country_customer_month_count * 0.05 AS INTEGER)
                + CASE
                    WHEN hr.country_customer_month_count * 0.05 > CAST(hr.country_customer_month_count * 0.05 AS INTEGER)
                    THEN 1
                    ELSE 0
                  END
            )
        END AS top_5_percent_country_cutoff
    FROM history_and_ranks AS hr
    JOIN country_medians AS cm
        ON cm.country_id = hr.country_id
       AND cm.payment_month = hr.payment_month
)
SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    country_name,
    payment_month,
    ROUND(monthly_payment_amount, 2) AS monthly_payment_amount,
    monthly_payment_count,
    ROUND(customer_avg_amount_prev_months, 2) AS customer_avg_amount_prev_months,
    ROUND(customer_avg_count_prev_months, 2) AS customer_avg_count_prev_months,
    ROUND(country_median_payment_amount, 2) AS country_median_payment_amount,
    ROUND(country_median_payment_count, 2) AS country_median_payment_count,
    ROUND(monthly_payment_amount / NULLIF(customer_avg_amount_prev_months, 0), 2) AS amount_to_own_history_ratio,
    ROUND(monthly_payment_count / NULLIF(customer_avg_count_prev_months, 0), 2) AS count_to_own_history_ratio,
    ROUND(monthly_payment_amount / NULLIF(country_median_payment_amount, 0), 2) AS amount_to_country_median_ratio,
    ROUND(monthly_payment_count / NULLIF(country_median_payment_count, 0), 2) AS count_to_country_median_ratio,
    distinct_staff_count,
    distinct_store_count,
    ROUND(max_payment_amount, 2) AS max_payment_amount,
    first_payment_date,
    last_payment_date,
    country_amount_rank,
    country_customer_month_count,
    CASE
        WHEN customer_avg_amount_prev_months IS NOT NULL
             AND monthly_payment_amount >= 3 * customer_avg_amount_prev_months
             AND country_amount_rank <= top_5_percent_country_cutoff
        THEN 'OWN_HISTORY_3X_AND_COUNTRY_TOP_5_PERCENT'
        WHEN customer_avg_amount_prev_months IS NOT NULL
             AND monthly_payment_amount >= 3 * customer_avg_amount_prev_months
        THEN 'OWN_HISTORY_3X'
        WHEN country_amount_rank <= top_5_percent_country_cutoff
        THEN 'COUNTRY_TOP_5_PERCENT'
    END AS suspicion_reason
FROM scored
WHERE
    (
        customer_avg_amount_prev_months IS NOT NULL
        AND monthly_payment_amount >= 3 * customer_avg_amount_prev_months
    )
    OR country_amount_rank <= top_5_percent_country_cutoff
ORDER BY
    payment_month,
    country_name,
    country_amount_rank,
    monthly_payment_amount DESC,
    customer_id;