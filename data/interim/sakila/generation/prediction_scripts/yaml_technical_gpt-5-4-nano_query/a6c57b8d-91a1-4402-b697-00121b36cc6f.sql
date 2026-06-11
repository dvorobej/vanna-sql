WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS payment_amount,
        p.p06 AS payment_date,
        date(p.p06, 'start of month') AS month_start
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
customer_monthly AS (
    SELECT
        p.customer_id,
        p.month_start,
        COUNT(p.payment_id) AS payment_count,
        SUM(CAST(p.payment_amount AS REAL)) AS month_total_amount
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.month_start
),
customer_history_avg AS (
    SELECT
        cm.customer_id,
        AVG(cm.month_total_amount) AS personal_avg_month_amount
    FROM customer_monthly AS cm
    GROUP BY
        cm.customer_id
),
country_month_stats AS (
    SELECT
        cm.customer_id,
        c.h02 AS country_id,
        cm.month_start,
        cm.month_total_amount,
        cm.payment_count
    FROM customer_monthly AS cm
    JOIN cus AS c1 ON c1.h01 = cm.customer_id
    JOIN adr AS a ON a.e01 = c1.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ci.d03
),
country_month_rank AS (
    SELECT
        cms.*,
        RANK() OVER (
            PARTITION BY cms.country_id, cms.month_start
            ORDER BY cms.month_total_amount DESC
        ) AS country_month_amount_rank,
        COUNT(*) OVER (
            PARTITION BY cms.country_id, cms.month_start
        ) AS country_month_customers_cnt
    FROM country_month_stats AS cms
),
top_staff_per_month AS (
    SELECT
        p.customer_id,
        p.month_start,
        p.staff_id,
        SUM(CAST(p.payment_amount AS REAL)) AS staff_month_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.customer_id, p.month_start
            ORDER BY SUM(CAST(p.payment_amount AS REAL)) DESC, p.staff_id
        ) AS rn
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.month_start,
        p.staff_id
),
monthly_suspicious AS (
    SELECT
        cm.customer_id,
        cm.month_start,
        cm.payment_count,
        cm.month_total_amount,
        cha.personal_avg_month_amount,
        (cm.month_total_amount - cha.personal_avg_month_amount) AS deviation_from_personal_avg,
        CAST(
            (cm.month_total_amount * 1.0) / NULLIF(cha.personal_avg_month_amount, 0)
            AS REAL
        ) AS ratio_to_personal_avg,
        cmr.country_id,
        cmr.country_month_amount_rank,
        cmr.country_month_customers_cnt,
        CAST(
            (cmr.country_month_amount_rank - 1) * 1.0 / NULLIF(cmr.country_month_customers_cnt, 0)
            AS REAL
        ) AS country_share_excluding_top1
    FROM customer_monthly AS cm
    JOIN customer_history_avg AS cha
      ON cha.customer_id = cm.customer_id
    JOIN country_month_rank AS cmr
      ON cmr.customer_id = cm.customer_id
     AND cmr.month_start = cm.month_start
)
SELECT
    ms.customer_id,
    cu.h03 || ' ' || cu.h04 AS customer_name,
    cn.c02 AS country,
    ct.d02 AS city,
    strftime('%Y-%m', ms.month_start) AS month,
    ROUND(ms.month_total_amount, 2) AS month_total_amount,
    ms.payment_count,
    ROUND(ms.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    ms.country_month_amount_rank AS country_customer_amount_rank,
    stf.o01 AS staff_id,
    stf.o02 || ' ' || stf.o03 AS staff_name,
    ROUND(tsp.staff_month_amount, 2) AS top_staff_month_amount
FROM monthly_suspicious AS ms
JOIN cus AS cu
  ON cu.h01 = ms.customer_id
JOIN adr AS a
  ON a.e01 = cu.h06
JOIN cty AS ct
  ON ct.d01 = a.e05
JOIN cnt AS cn
  ON cn.c01 = ct.d03
JOIN top_staff_per_month AS tsp
  ON tsp.customer_id = ms.customer_id
 AND tsp.month_start = ms.month_start
 AND tsp.rn = 1
JOIN stf
  ON stf.o01 = tsp.staff_id
WHERE
    ms.personal_avg_month_amount > 0
    AND ms.month_total_amount > 2.0 * ms.personal_avg_month_amount
    AND ms.country_month_amount_rank <=
        CAST(ms.country_month_customers_cnt * 0.10 AS INTEGER) + CASE
            WHEN ms.country_month_customers_cnt * 0.10 > CAST(ms.country_month_customers_cnt * 0.10 AS INTEGER) THEN 1
            ELSE 0
        END
ORDER BY
    cn.c02,
    ms.month_start,
    ms.month_total_amount DESC,
    ms.customer_id;