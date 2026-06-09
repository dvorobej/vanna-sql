WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        s.o07 AS store_id
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06), s.o07
),
daily_aggregated AS (
    SELECT
        customer_id,
        payment_date,
        SUM(day_amount) AS total_day_amount,
        SUM(payment_count) AS total_payment_count,
        MAX(store_id) AS store_id
    FROM daily_customer_payments
    GROUP BY customer_id, payment_date
),
customer_stats AS (
    SELECT
        da.*,
        (
            SELECT AVG(prev.total_day_amount)
            FROM daily_aggregated AS prev
            WHERE prev.customer_id = da.customer_id
              AND prev.payment_date >= DATE(da.payment_date, '-30 days')
              AND prev.payment_date < da.payment_date
        ) AS avg_30d
    FROM daily_aggregated AS da
),
country_percentiles AS (
    SELECT
        c.c01 AS country_id,
        da.total_day_amount
    FROM daily_aggregated AS da
    JOIN cus AS cu ON cu.h01 = da.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ci.d03
),
p95_values AS (
    SELECT
        country_id,
        MAX(total_day_amount) AS p95_val
    FROM (
        SELECT
            country_id,
            total_day_amount,
            PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY total_day_amount) as pr
        FROM country_percentiles
    )
    WHERE pr <= 0.95
    GROUP BY country_id
)
SELECT
    cs.payment_date,
    cu.h03 AS first_name,
    cu.h04 AS last_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    cs.store_id,
    cs.total_payment_count,
    ROUND(cs.total_day_amount, 2) AS total_day_amount,
    ROUND(cs.avg_30d, 2) AS avg_30d,
    ROUND(cs.total_day_amount - cs.avg_30d, 2) AS deviation,
    RANK() OVER (PARTITION BY cnt.c01 ORDER BY cs.total_day_amount DESC) AS country_rank
FROM customer_stats AS cs
JOIN cus AS cu ON cu.h01 = cs.customer_id
JOIN adr AS a ON a.e01 = cu.h06
JOIN cty AS cty ON cty.d01 = a.e05
JOIN cnt AS cnt ON cnt.c01 = cty.d03
JOIN p95_values AS p95 ON p95.country_id = cnt.c01
WHERE cs.avg_30d > 0
  AND cs.total_day_amount >= 3 * cs.avg_30d
  AND cs.total_day_amount > p95.p95_val
ORDER BY cnt.c02, cs.total_day_amount DESC;