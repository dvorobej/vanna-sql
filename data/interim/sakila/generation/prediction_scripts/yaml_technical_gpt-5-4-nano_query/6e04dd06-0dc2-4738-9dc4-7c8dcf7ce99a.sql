WITH monthly_customer AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month_ym,
        SUM(p.p05) AS month_amount,
        COUNT(*) AS month_payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
customer_with_prev AS (
    SELECT
        mc.*,
        (
            SELECT AVG(m2.month_amount) * 1.0
            FROM monthly_customer AS m2
            WHERE m2.customer_id = mc.customer_id
              AND m2.month_ym < mc.month_ym
              AND m2.month_ym >= strftime('%Y-%m', date(substr(mc.month_ym,1,4) || '-01-01', '+0 months')) -- dummy
        ) AS dummy
    FROM monthly_customer mc
),
monthly_customer_with_history AS (
    SELECT
        mc.*,
        (
            SELECT AVG(m2.month_amount)
            FROM monthly_customer AS m2
            WHERE m2.customer_id = mc.customer_id
              AND m2.month_ym < mc.month_ym
              AND m2.month_ym >= strftime('%Y-%m', date(mc.month_ym || '-01', '-3 months'))
              AND m2.month_ym <  strftime('%Y-%m', date(mc.month_ym || '-01', '-0 months'))
        ) AS avg_prev_3_month_amount
    FROM monthly_customer mc
),
country_month_rank AS (
    SELECT
        mcwh.*,
        PERCENT_RANK() OVER (
            PARTITION BY (SELECT 1) 
            ) AS dummy2
    FROM monthly_customer_with_history mcwh
),
country_month_stats AS (
    SELECT
        mcwh.customer_id,
        mcwh.month_ym,
        mcwh.month_amount,
        mcwh.month_payment_count,
        mcwh.distinct_staff_count,
        mcwh.distinct_store_count,
        cty.c01 AS country_id,
        cty.c02 AS country_name,
        (
            SELECT AVG(cm2.month_amount)
            FROM monthly_customer_with_history cm2
            WHERE cm2.month_ym = mcwh.month_ym
              AND cm2.customer_id IN (
                SELECT c3.h01
                FROM cus c3
                JOIN adr a3 ON a3.e01 = c3.h06
                JOIN cty ci3 ON ci3.d01 = a3.e05
                JOIN cnt cty3 ON cty3.c01 = ci3.d03
                WHERE c3.h01 = c3.h01
              )
        ) AS dummy3
    FROM monthly_customer_with_history mcwh
    JOIN cus c
        ON c.h01 = mcwh.customer_id
    JOIN adr a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt cty
        ON cty.c01 = cty.d03
),
-- recompute properly with median and top 5% using country partition
country_month_enriched AS (
    SELECT
        mc.customer_id,
        mc.month_ym,
        mc.month_amount,
        mc.month_payment_count,
        mc.distinct_staff_count,
        mc.distinct_store_count,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM monthly_customer mc
    JOIN cus c
        ON c.h01 = mc.customer_id
    JOIN adr a
        ON a.e01 = c.h06
    JOIN cty city
        ON city.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = city.d03
),
country_month_ordered AS (
    SELECT
        cme.*,
        ROW_NUMBER() OVER (
            PARTITION BY cme.country_id, cme.month_ym
            ORDER BY cme.month_amount DESC
        ) AS rn_desc,
        COUNT(*) OVER (
            PARTITION BY cme.country_id, cme.month_ym
        ) AS cnt_customers_in_country
    FROM country_month_enriched cme
),
country_month_median AS (
    -- median = average of middle one or two values
    SELECT
        cmo.country_id,
        cmo.month_ym,
        AVG(cmo.month_amount) AS country_median_month_amount
    FROM country_month_ordered cmo
    WHERE cmo.rn_desc IN (
        CAST((cmo.cnt_customers_in_country + 1) / 2 AS INTEGER),
        CAST((cmo.cnt_customers_in_country + 2) / 2 AS INTEGER)
    )
    GROUP BY
        cmo.country_id,
        cmo.month_ym
),
customer_prev_avg AS (
    SELECT
        mc.customer_id,
        mc.month_ym,
        (
            SELECT AVG(m2.month_amount)
            FROM monthly_customer m2
            WHERE m2.customer_id = mc.customer_id
              AND m2.month_ym >= strftime('%Y-%m', date(mc.month_ym || '-01', '-3 months'))
              AND m2.month_ym <  strftime('%Y-%m', date(mc.month_ym || '-01', '-0 months'))
        ) AS avg_prev_3_month_amount
    FROM monthly_customer mc
),
final_calc AS (
    SELECT
        cme.customer_id,
        cme.month_ym,
        cme.month_amount,
        cme.month_payment_count,
        cme.distinct_staff_count,
        cme.distinct_store_count,
        cme.country_name,
        cp.avg_prev_3_month_amount,
        cmm.country_median_month_amount,
        cmo.rn_desc,
        cmo.cnt_customers_in_country
    FROM country_month_enriched cme
    JOIN customer_prev_avg cp
        ON cp.customer_id = cme.customer_id
       AND cp.month_ym = cme.month_ym
    JOIN country_month_median cmm
        ON cmm.country_id = cme.country_id
       AND cmm.month_ym = cme.month_ym
    JOIN country_month_ordered cmo
        ON cmo.customer_id = cme.customer_id
       AND cmo.month_ym = cme.month_ym
       AND cmo.country_id = cme.country_id
)
SELECT
    fc.customer_id,
    cus.h03 AS customer_first_name,
    cus.h04 AS customer_last_name,
    fc.country_name,
    fc.month_ym AS month,
    ROUND(fc.month_amount, 2) AS month_amount,
    fc.month_payment_count,
    fc.distinct_staff_count,
    fc.distinct_store_count,
    ROUND(fc.avg_prev_3_month_amount, 2) AS avg_prev_3_month_amount,
    ROUND(fc.country_median_month_amount, 2) AS country_median_month_amount,
    ROUND(fc.month_amount / NULLIF(fc.avg_prev_3_month_amount, 0), 2) AS vs_personal_history_ratio,
    ROUND(fc.month_amount / NULLIF(fc.country_median_month_amount, 0), 2) AS vs_country_median_ratio,
    fc.rn_desc AS country_month_rank_desc
FROM final_calc fc
JOIN cus
    ON cus.h01 = fc.customer_id
WHERE fc.avg_prev_3_month_amount IS NOT NULL
  AND fc.avg_prev_3_month_amount > 0
  AND fc.month_amount >= 3.0 * fc.avg_prev_3_month_amount
  AND fc.month_amount >= 2.0 * fc.country_median_month_amount
  AND fc.rn_desc <= CAST(0.05 * fc.cnt_customers_in_country AS INTEGER) + 1
ORDER BY
    fc.country_name,
    fc.month_ym,
    fc.rn_desc;