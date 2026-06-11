WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p06) AS last_payment_date
    FROM pay AS p
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_yearly_avg AS (
    SELECT
        customer_id,
        AVG(monthly_sum) AS avg_monthly_sum
    FROM monthly_stats
    GROUP BY customer_id
),
store_monthly_rank AS (
    SELECT
        ms.customer_id,
        ms.payment_month,
        ms.monthly_sum,
        ms.payment_count,
        c.h02 AS store_id,
        c.h03, c.h04,
        a.e05 AS city_id,
        ct.d03 AS country_id,
        PERCENT_RANK() OVER (PARTITION BY c.h02, ms.payment_month ORDER BY ms.monthly_sum DESC) AS store_percentile,
        (ms.monthly_sum - cya.avg_monthly_sum) AS deviation
    FROM monthly_stats ms
    JOIN cus c ON ms.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN customer_yearly_avg cya ON ms.customer_id = cya.customer_id
),
last_staff AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id
    FROM pay p
    WHERE (p.p02, p.p06) IN (
        SELECT p02, MAX(p06) FROM pay GROUP BY p02, strftime('%Y-%m', p06)
    )
)
SELECT
    smr.payment_month,
    smr.h03 || ' ' || smr.h04 AS customer_name,
    smr.store_id,
    cnt.c02 AS country,
    ct.d02 AS city,
    smr.monthly_sum,
    smr.payment_count,
    ROUND(smr.deviation, 2) AS deviation_from_avg,
    RANK() OVER (PARTITION BY smr.store_id, smr.payment_month ORDER BY smr.monthly_sum DESC) AS store_rank,
    ls.staff_id AS last_staff_id
FROM store_monthly_rank smr
JOIN cnt ON smr.country_id = cnt.c01
JOIN cty ct ON smr.city_id = ct.d01
JOIN last_staff ls ON smr.customer_id = ls.customer_id AND smr.payment_month = ls.payment_month
WHERE smr.monthly_sum > (SELECT avg_monthly_sum FROM customer_yearly_avg WHERE customer_id = smr.customer_id)
  AND smr.store_percentile <= 0.05
ORDER BY smr.payment_month, smr.store_id, smr.monthly_sum DESC;