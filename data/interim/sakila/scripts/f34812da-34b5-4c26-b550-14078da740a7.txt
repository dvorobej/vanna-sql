WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        cn.c02 AS country,
        ct.d02 AS city,
        p.p05 AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        CASE
            WHEN r.q01 IS NOT NULL
             AND r.q05 IS NOT NULL
             AND f.i07 IS NOT NULL
             AND julianday(r.q05) > julianday(r.q02) + f.i07
            THEN 1
            ELSE 0
        END AS is_late_return
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN flm AS f ON f.i01 = i.n02
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
customer_month AS (
    SELECT
        customer_id,
        customer_name,
        payment_month,
        country,
        city,
        SUM(payment_amount) AS total_payment_amount,
        COUNT(*) AS operation_count,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count,
        SUM(is_late_return) * 1.0 / COUNT(*) AS late_return_share
    FROM payment_enriched
    GROUP BY
        customer_id,
        customer_name,
        payment_month,
        country,
        city
),
ranked_customer_month AS (
    SELECT
        customer_month.*,
        AVG(total_payment_amount) OVER (
            PARTITION BY country, payment_month
        ) AS avg_country_month_amount,
        RANK() OVER (
            PARTITION BY country, payment_month
            ORDER BY total_payment_amount DESC
        ) AS country_month_rank
    FROM customer_month
)
SELECT
    customer_id,
    customer_name,
    payment_month,
    country,
    city,
    ROUND(total_payment_amount, 2) AS total_payment_amount,
    operation_count,
    ROUND(late_return_share, 4) AS late_return_share,
    country_month_rank
FROM ranked_customer_month
WHERE total_payment_amount > avg_country_month_amount * 1.5
  AND operation_count >= 3
  AND (
      distinct_staff_count > 1
      OR distinct_store_count > 1
  )
ORDER BY
    country,
    payment_month,
    country_month_rank,
    customer_id;