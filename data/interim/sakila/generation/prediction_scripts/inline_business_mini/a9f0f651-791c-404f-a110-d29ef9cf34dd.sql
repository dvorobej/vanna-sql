WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT st.o07) AS distinct_store_count
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h07 AS active_flag,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d01 AS city_id,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
customer_months AS (
    SELECT
        cg.customer_id,
        cg.customer_name,
        cg.active_flag,
        cg.country_id,
        cg.country_name,
        cg.city_id,
        cg.city_name,
        mp.payment_month,
        COALESCE(mp.payment_count, 0) AS payment_count,
        COALESCE(mp.monthly_amount, 0.0) AS monthly_amount,
        COALESCE(mp.distinct_staff_count, 0) AS distinct_staff_count,
        COALESCE(mp.distinct_store_count, 0) AS distinct_store_count
    FROM customer_geo AS cg
    JOIN monthly_payments AS mp
      ON mp.customer_id = cg.customer_id
    WHERE cg.active_flag IN ('1', 'Y')
),
customer_history AS (
    SELECT
        cm.*,
        AVG(cm.monthly_amount) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_monthly_amount
    FROM customer_months AS cm
),
country_month_stats AS (
    SELECT
        cg.country_id,
        mp.payment_month,
        AVG(mp.payment_count * 1.0) AS avg_country_payment_count,
        COUNT(*) AS country_customer_count
    FROM monthly_payments AS mp
    JOIN customer_geo AS cg
      ON cg.customer_id = mp.customer_id
    GROUP BY
        cg.country_id,
        mp.payment_month
),
country_month_ranked AS (
    SELECT
        ch.*,
        cms.avg_country_payment_count,
        cms.country_customer_count,
        RANK() OVER (
            PARTITION BY ch.country_id, ch.payment_month
            ORDER BY ch.monthly_amount DESC
        ) AS country_amount_rank
    FROM customer_history AS ch
    JOIN country_month_stats AS cms
      ON cms.country_id = ch.country_id
     AND cms.payment_month = ch.payment_month
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    payment_month,
    payment_count,
    ROUND(monthly_amount, 2) AS monthly_amount,
    ROUND(prev_avg_monthly_amount, 2) AS prev_avg_monthly_amount,
    ROUND(monthly_amount - prev_avg_monthly_amount, 2) AS deviation_from_prev_avg,
    distinct_staff_count,
    distinct_store_count,
    country_amount_rank
FROM country_month_ranked
WHERE prev_avg_monthly_amount IS NOT NULL
  AND prev_avg_monthly_amount > 0
  AND monthly_amount >= 3.0 * prev_avg_monthly_amount
  AND payment_count > avg_country_payment_count
  AND (distinct_staff_count > 1 OR distinct_store_count > 1)
ORDER BY
    payment_month,
    country_name,
    country_amount_rank,
    monthly_amount DESC;