WITH customer_month_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS pay_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS total_amount,
        AVG(p.p05) AS average_payment,
        COUNT(DISTINCT p.p03) AS staff_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
        c.h01, c.h03, c.h04,
        cn.c01, cn.c02,
        strftime('%Y-%m', p.p06)
),
country_month_stats AS (
    SELECT
        country_id,
        pay_month,
        AVG(payment_count) AS avg_payment_count,
        COUNT(*) AS country_customer_count
    FROM customer_month_payments
    GROUP BY country_id, pay_month
),
ranked_months AS (
    SELECT
        cmp.*,
        RANK() OVER (
            PARTITION BY cmp.country_id, cmp.pay_month
            ORDER BY cmp.total_amount DESC, cmp.customer_id
        ) AS country_amount_rank,
        COUNT(*) OVER (
            PARTITION BY cmp.country_id, cmp.pay_month
        ) AS country_customers_in_month,
        CUME_DIST() OVER (
            PARTITION BY cmp.country_id, cmp.pay_month
            ORDER BY cmp.total_amount
        ) AS country_amount_cume
    FROM customer_month_payments AS cmp
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS pay_date,
        p.p06 AS pay_ts
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
streaks AS (
    SELECT
        d1.customer_id,
        d1.pay_date
    FROM daily_payments AS d1
    WHERE EXISTS (
        SELECT 1
        FROM daily_payments AS d2
        JOIN daily_payments AS d3
          ON d3.customer_id = d1.customer_id
         AND d3.pay_ts > d2.pay_ts
         AND julianday(d3.pay_ts) - julianday(d2.pay_ts) <= 1.0
        WHERE d2.customer_id = d1.customer_id
          AND d2.pay_ts >= datetime(d1.pay_ts, '-24 hours')
          AND d2.pay_ts <= d1.pay_ts
        GROUP BY d1.customer_id
        HAVING COUNT(*) >= 3
    )
),
streak_customers AS (
    SELECT DISTINCT customer_id
    FROM streaks
)
SELECT
    r.customer_id,
    r.first_name,
    r.last_name,
    r.country_name,
    r.pay_month AS month,
    r.payment_count,
    ROUND(r.total_amount, 2) AS total_amount,
    ROUND(r.average_payment, 2) AS average_payment,
    r.staff_count,
    r.country_amount_rank AS country_month_rank
FROM ranked_months AS r
JOIN country_month_stats AS cms
  ON cms.country_id = r.country_id
 AND cms.pay_month = r.pay_month
JOIN streak_customers AS sc
  ON sc.customer_id = r.customer_id
WHERE r.country_amount_cume >= 0.90
  AND r.payment_count > cms.avg_payment_count
  AND r.staff_count = 2
  AND r.country_customers_in_month > 0
ORDER BY
    r.pay_month,
    r.country_name,
    r.total_amount DESC,
    r.customer_id;