WITH payments_2005 AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS home_store_id,
        DATE(p.p06, 'start of month') AS month_start,
        p.p06 AS payment_dt,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
monthly_customer AS (
    SELECT
        customer_id,
        home_store_id,
        month_start,
        SUM(payment_amount) AS monthly_amount_sum,
        COUNT(*) AS monthly_payment_count,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count
    FROM payments_2005
    GROUP BY customer_id, home_store_id, month_start
),
history_3prev AS (
    SELECT
        mc.*,
        (
            SELECT AVG(m2.monthly_amount_sum)
            FROM monthly_customer m2
            WHERE m2.customer_id = mc.customer_id
              AND m2.month_start < mc.month_start
              AND m2.month_start >= DATE(mc.month_start, '-3 months')
        ) AS avg_prev_3_months_amount
    FROM monthly_customer mc
),
country_month_rank AS (
    SELECT
        mc.*,
        ROW_NUMBER() OVER (PARTITION BY mc.month_start, mc.customer_id / mc.customer_id ORDER BY mc.monthly_amount_sum DESC) AS dummy
    FROM history_3prev mc
    WHERE 1=1
),
monthly_with_country AS (
    SELECT
        h3.customer_id,
        h3.home_store_id,
        h3.month_start,
        h3.monthly_amount_sum,
        h3.monthly_payment_count,
        h3.distinct_staff_count,
        h3.distinct_store_count,
        co.c01 AS country_id,
        co.c02 AS country_name
    FROM history_3prev h3
    JOIN cus c ON c.h01 = h3.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
country_months_sorted AS (
    SELECT
        mwc.*,
        COUNT(*) OVER (PARTITION BY mwc.country_id, mwc.month_start) AS country_month_customers_cnt,
        RANK() OVER (
            PARTITION BY mwc.country_id, mwc.month_start
            ORDER BY mwc.monthly_amount_sum DESC
        ) AS country_month_rank
    FROM monthly_with_country mwc
),
country_month_median AS (
    -- медиана: берём значение по позиции (n+1)/2 и (n+2)/2 и усредняем
    SELECT
        cm.country_id,
        cm.month_start,
        AVG(cm.monthly_amount_sum) AS country_month_median_amount
    FROM (
        SELECT
            cms.*,
            ROW_NUMBER() OVER (
                PARTITION BY cms.country_id, cms.month_start
                ORDER BY cms.monthly_amount_sum DESC
            ) AS rn,
            COUNT(*) OVER (PARTITION BY cms.country_id, cms.month_start) AS n
        FROM country_months_sorted cms
    ) cm
    WHERE cm.rn IN (
        CAST((cm.n + 1) / 2 AS INTEGER),
        CAST((cm.n + 2) / 2 AS INTEGER)
    )
    GROUP BY cm.country_id, cm.month_start
),
joined AS (
    SELECT
        cms.country_name,
        cms.customer_id,
        cus.h03 AS customer_first_name,
        cus.h04 AS customer_last_name,
        cms.home_store_id,
        cms.month_start,
        cms.monthly_amount_sum,
        cms.monthly_payment_count,
        cms.distinct_staff_count,
        cms.distinct_store_count,
        cms.avg_prev_3_months_amount,
        cmed.country_month_median_amount,
        cms.country_month_customers_cnt,
        cms.country_month_rank,
        cms.monthly_amount_sum / NULLIF(cmed.country_month_median_amount, 0) AS ratio_to_country_median,
        cms.monthly_amount_sum / NULLIF(cms.avg_prev_3_months_amount, 0) AS ratio_to_own_avg_prev_3
    FROM (
        SELECT
            mwc.*,
            h3.avg_prev_3_months_amount,
            mwc.monthly_payment_sum_placeholder
        FROM monthly_with_country mwc
        LEFT JOIN history_3prev h3
          ON h3.customer_id = mwc.customer_id
         AND h3.month_start = mwc.month_start
    ) cms
    JOIN monthly_with_country cms2
      ON cms2.customer_id = cms.customer_id
     AND cms2.month_start = cms.month_start
    JOIN cus ON cus.h01 = cms.customer_id
    LEFT JOIN country_month_median cmed
      ON cmed.country_id = cms.country_id
     AND cmed.month_start = cms.month_start
)
SELECT
    j.customer_id,
    j.customer_first_name,
    j.customer_last_name,
    j.country_name,
    j.month_start AS month,
    ROUND(j.monthly_amount_sum, 2) AS monthly_payment_sum,
    j.monthly_payment_count,
    j.distinct_staff_count,
    j.distinct_store_count,
    ROUND(j.avg_prev_3_months_amount, 2) AS avg_prev_3_months_amount,
    ROUND(j.country_month_median_amount, 2) AS country_month_median_amount,
    ROUND(j.ratio_to_own_avg_prev_3, 2) AS ratio_to_own_avg_prev_3_months,
    ROUND(j.ratio_to_country_median, 2) AS ratio_to_country_median,
    j.country_month_rank AS country_month_rank_top_case
FROM (
    SELECT
        mwc2.*,
        h3.avg_prev_3_months_amount,
        cmed.country_month_median_amount,
        cmss.country_month_customers_cnt,
        cmss.country_month_rank,
        ROUND(mwc2.monthly_amount_sum / NULLIF(h3.avg_prev_3_months_amount, 0), 4) AS ratio_to_own_avg_prev_3,
        ROUND(mwc2.monthly_amount_sum / NULLIF(cmed.country_month_median_amount, 0), 4) AS ratio_to_country_median,
        ROUND(h3.avg_prev_3_months_amount, 2) AS avg_prev_3_months_amount_rounded,
        cmss.country_month_customers_cnt AS country_month_customers_cnt2
    FROM monthly_with_country mwc2
    JOIN history_3prev h3
      ON h3.customer_id = mwc2.customer_id
     AND h3.month_start = mwc2.month_start
    JOIN country_months_sorted cmss
      ON cmss.customer_id = mwc2.customer_id
     AND cmss.month_start = mwc2.month_start
     AND cmss.country_id = mwc2.country_id
    LEFT JOIN country_month_median cmed
      ON cmed.country_id = mwc2.country_id
     AND cmed.month_start = mwc2.month_start
) j
JOIN cus
  ON cus.h01 = j.customer_id
WHERE j.avg_prev_3_months_amount IS NOT NULL
  AND j.avg_prev_3_months_amount > 0
  AND j.ratio_to_own_avg_prev_3 >= 3
  AND j.ratio_to_country_median >= 2
  AND j.country_month_rank <= CAST((j.country_month_customers_cnt2 * 0.05) + 0.999999 AS INTEGER)
ORDER BY
  j.country_name,
  month,
  monthly_payment_sum DESC,
  j.customer_id;