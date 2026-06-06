WITH customer_day_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_sum
    FROM pay AS p
    GROUP BY
        p.p02,
        DATE(p.p06)
),
customer_day_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st
        ON st.o01 = p.p03
    GROUP BY
        p.p02,
        DATE(p.p06)
),
customer_day_history AS (
    SELECT
        cdp.customer_id,
        cdp.payment_day,
        cdp.payment_count,
        cdp.day_sum,
        (
            SELECT AVG(prev.day_sum)
            FROM customer_day_payments AS prev
            WHERE prev.customer_id = cdp.customer_id
              AND prev.payment_day >= DATE(cdp.payment_day, '-30 days')
              AND prev.payment_day < cdp.payment_day
        ) AS avg_prev_30d_day_sum
    FROM customer_day_payments AS cdp
),
eligible_days AS (
    SELECT
        cdh.customer_id,
        cdh.payment_day,
        cdh.payment_count,
        cdh.day_sum,
        cdh.avg_prev_30d_day_sum,
        (cdh.day_sum - cdh.avg_prev_30d_day_sum) AS deviation_from_average
    FROM customer_day_history AS cdh
    JOIN customer_day_staff_store AS cdss
        ON cdss.customer_id = cdh.customer_id
       AND cdss.payment_day = cdh.payment_day
    WHERE cdh.payment_count >= 3
      AND cdh.avg_prev_30d_day_sum IS NOT NULL
      AND cdh.avg_prev_30d_day_sum > 0
      AND cdh.day_sum >= 3 * cdh.avg_prev_30d_day_sum
      AND (cdss.staff_count > 1 OR cdss.store_count > 1)
)
SELECT
    ed.customer_id,
    cu.h03 || ' ' || cu.h04 AS customer_name,
    cn.c02 AS country,
    ct.d02 AS city,
    ed.payment_day,
    ed.payment_count,
    ROUND(ed.day_sum, 2) AS day_sum,
    ROUND(ed.avg_prev_30d_day_sum, 2) AS avg_prev_30d_day_sum,
    ROUND(ed.deviation_from_average, 2) AS deviation_from_average,
    RANK() OVER (
        ORDER BY ed.deviation_from_average DESC
    ) AS risk_rank
FROM eligible_days AS ed
JOIN cus AS cu
    ON cu.h01 = ed.customer_id
JOIN adr AS ad
    ON ad.e01 = cu.h06
JOIN cty AS ct
    ON ct.d01 = ad.e05
JOIN cnt AS cn
    ON cn.c01 = ct.d03
ORDER BY
    risk_rank,
    ed.customer_id,
    ed.payment_day;