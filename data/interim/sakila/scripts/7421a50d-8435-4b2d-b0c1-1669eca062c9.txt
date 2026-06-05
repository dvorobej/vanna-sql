WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        h.h03 || ' ' || h.h04 AS customer_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        p.p05 AS amount,
        p.p06 AS payment_date
    FROM pay AS p
    JOIN cus AS h ON h.h01 = p.p02
    JOIN adr AS e ON e.e01 = h.h06
    JOIN cty AS d ON d.d01 = e.e05
    JOIN cnt AS co ON co.c01 = d.d03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
monthly_customer AS (
    SELECT
        country_id,
        country_name,
        payment_month,
        customer_id,
        customer_name,
        COUNT(*) AS payment_count,
        SUM(amount) AS monthly_amount,
        AVG(amount) AS avg_payment,
        COUNT(DISTINCT staff_id) AS staff_count
    FROM payment_base
    GROUP BY
        country_id,
        country_name,
        payment_month,
        customer_id,
        customer_name
),
country_month_stats AS (
    SELECT
        country_id,
        payment_month,
        AVG(payment_count * 1.0) AS country_avg_payment_count,
        COUNT(*) AS customers_in_country_month
    FROM monthly_customer
    GROUP BY country_id, payment_month
),
ranked_customers AS (
    SELECT
        mc.*,
        cms.country_avg_payment_count,
        cms.customers_in_country_month,
        RANK() OVER (
            PARTITION BY mc.country_id, mc.payment_month
            ORDER BY mc.monthly_amount DESC
        ) AS amount_rank
    FROM monthly_customer AS mc
    JOIN country_month_stats AS cms
      ON cms.country_id = mc.country_id
     AND cms.payment_month = mc.payment_month
),
burst_customers AS (
    SELECT DISTINCT
        b1.customer_id,
        b1.payment_month
    FROM payment_base AS b1
    JOIN payment_base AS b2
      ON b2.customer_id = b1.customer_id
     AND b2.payment_month = b1.payment_month
     AND julianday(b2.payment_date) >= julianday(b1.payment_date)
     AND julianday(b2.payment_date) <= julianday(b1.payment_date) + 1
    GROUP BY
        b1.customer_id,
        b1.payment_month,
        b1.payment_id
    HAVING COUNT(*) >= 3
)
SELECT
    r.customer_id,
    r.customer_name AS customer,
    r.country_name AS country,
    r.payment_month AS month,
    r.payment_count,
    ROUND(r.monthly_amount, 2) AS monthly_sum,
    ROUND(r.avg_payment, 2) AS avg_payment,
    r.staff_count,
    r.amount_rank AS country_month_rank
FROM ranked_customers AS r
JOIN burst_customers AS b
  ON b.customer_id = r.customer_id
 AND b.payment_month = r.payment_month
WHERE r.amount_rank <= CAST((r.customers_in_country_month + 9) / 10 AS INTEGER)
  AND r.payment_count > r.country_avg_payment_count
  AND r.staff_count = (SELECT COUNT(*) FROM stf)
ORDER BY
    r.payment_month,
    r.country_name,
    r.amount_rank,
    r.monthly_amount DESC,
    r.customer_id;