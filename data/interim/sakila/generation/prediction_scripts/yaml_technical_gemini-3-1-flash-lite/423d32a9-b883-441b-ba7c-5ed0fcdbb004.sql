WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT c.h02) AS store_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_avg AS (
    SELECT
        mp.customer_id,
        mp.payment_month,
        mp.monthly_sum,
        mp.payment_count,
        mp.staff_count,
        mp.store_count,
        (
            SELECT AVG(mp2.monthly_sum)
            FROM pay AS p2
            JOIN cus AS c2 ON c2.h01 = p2.p02
            JOIN (SELECT p02, strftime('%Y-%m', p06) AS m, SUM(p05) AS s FROM pay GROUP BY p02, strftime('%Y-%m', p06)) AS mp2
              ON mp2.p02 = mp.customer_id AND mp2.m < mp.payment_month
        ) AS prev_avg_sum
    FROM monthly_payments AS mp
),
filtered_anomalies AS (
    SELECT
        ha.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id
    FROM history_avg AS ha
    JOIN cus AS c ON c.h01 = ha.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE ha.prev_avg_sum IS NOT NULL
      AND ha.monthly_sum >= 2 * ha.prev_avg_sum
      AND ha.payment_count >= 5
      AND (ha.staff_count > 1 OR ha.store_count > 1)
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    ROUND(monthly_sum, 2) AS monthly_sum,
    payment_count,
    ROUND(prev_avg_sum, 2) AS prev_avg_sum,
    RANK() OVER (
        PARTITION BY country_id, payment_month
        ORDER BY (monthly_sum - prev_avg_sum) DESC
    ) AS country_anomaly_rank
FROM filtered_anomalies
ORDER BY
    country,
    payment_month,
    country_anomaly_rank;