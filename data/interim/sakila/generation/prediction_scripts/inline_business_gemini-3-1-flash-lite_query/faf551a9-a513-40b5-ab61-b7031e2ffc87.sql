WITH daily_payments AS (
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
customer_daily_summary AS (
    SELECT
        customer_id,
        payment_date,
        SUM(day_amount) AS total_day_amount,
        SUM(payment_count) AS total_payment_count,
        GROUP_CONCAT(DISTINCT store_id) AS stores
    FROM daily_payments
    GROUP BY customer_id, payment_date
),
with_personal_avg AS (
    SELECT
        cds.*,
        (
            SELECT AVG(prev.total_day_amount)
            FROM customer_daily_summary AS prev
            WHERE prev.customer_id = cds.customer_id
              AND prev.payment_date >= DATE(cds.payment_date, '-30 days')
              AND prev.payment_date < cds.payment_date
        ) AS avg_30d
    FROM customer_daily_summary AS cds
),
country_percentiles AS (
    SELECT
        c.c01 AS country_id,
        (SELECT val FROM (
            SELECT total_day_amount AS val,
                   PERCENT_RANK() OVER (ORDER BY total_day_amount) AS pr
            FROM customer_daily_summary cds2
            JOIN cus c2 ON c2.h01 = cds2.customer_id
            JOIN adr a ON a.e01 = c2.h06
            JOIN cty ct ON ct.d01 = a.e05
            WHERE ct.d03 = c.c01
        ) WHERE pr >= 0.95 LIMIT 1) AS p95_val
    FROM cnt c
),
suspicious_days AS (
    SELECT
        wpa.*,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id
    FROM with_personal_avg AS wpa
    JOIN cus AS c ON c.h01 = wpa.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    JOIN country_percentiles AS cp ON cp.country_id = cnt.c01
    WHERE wpa.avg_30d > 0
      AND wpa.total_day_amount >= 3 * wpa.avg_30d
      AND wpa.total_day_amount > cp.p95_val
)
SELECT
    payment_date,
    first_name,
    last_name,
    country_name,
    city_name,
    stores,
    total_payment_count,
    ROUND(total_day_amount, 2) AS day_amount,
    ROUND(avg_30d, 2) AS avg_30d,
    ROUND(total_day_amount - avg_30d, 2) AS deviation,
    RANK() OVER (PARTITION BY country_id ORDER BY total_day_amount DESC) AS country_rank
FROM suspicious_days
ORDER BY country_name, country_rank;