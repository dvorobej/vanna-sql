WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count
    FROM pay p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (PARTITION BY customer_id) AS avg_monthly_amount
    FROM monthly_customer_stats
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        PERCENT_RANK() OVER (PARTITION BY cnt.c01, mcs.payment_month ORDER BY mcs.monthly_amount) AS country_percentile
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
top_staff_per_month AS (
    SELECT customer_id, payment_month, staff_id,
           ROW_NUMBER() OVER (PARTITION BY customer_id, payment_month ORDER BY total_staff_amount DESC) as rn
    FROM (
        SELECT p.p02 AS customer_id, strftime('%Y-%m', p.p06) AS payment_month, p.p03 AS staff_id, SUM(p.p05) AS total_staff_amount
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    )
)
SELECT
    ch.customer_id,
    cs.country,
    cs.city,
    ch.payment_month,
    ch.monthly_amount,
    ch.payment_count,
    ROUND(ch.monthly_amount / NULLIF(ch.avg_monthly_amount, 0), 2) AS deviation_ratio,
    RANK() OVER (PARTITION BY cs.country_id, ch.payment_month ORDER BY ch.monthly_amount DESC) AS country_rank,
    ts.staff_id
FROM customer_history ch
JOIN country_stats cs ON cs.customer_id = ch.customer_id
JOIN top_staff_per_month ts ON ts.customer_id = ch.customer_id AND ts.payment_month = ch.payment_month AND ts.rn = 1
WHERE ch.monthly_amount > (2 * ch.avg_monthly_amount)
  AND cs.country_percentile >= 0.9
ORDER BY ch.payment_month, cs.country, country_rank;