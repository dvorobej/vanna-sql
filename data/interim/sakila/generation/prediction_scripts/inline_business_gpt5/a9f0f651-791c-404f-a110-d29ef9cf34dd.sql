WITH RECURSIVE
month_bounds AS (
    SELECT
        MIN(date(strftime('%Y-%m-01', p06))) AS min_month,
        date('2005-12-01') AS max_month
    FROM pay
    WHERE p06 < '2006-01-01'
),
months(month_start) AS (
    SELECT min_month
    FROM month_bounds
    WHERE min_month IS NOT NULL
      AND min_month <= max_month

    UNION ALL

    SELECT date(month_start, '+1 month')
    FROM months, month_bounds
    WHERE month_start < max_month
),
active_customers AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        date(strftime('%Y-%m-01', c.h08)) AS registration_month,
        city.d01 AS city_id,
        city.d02 AS city_name,
        country.c01 AS country_id,
        country.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty AS city
      ON city.d01 = a.e05
    JOIN cnt AS country
      ON country.c01 = city.d03
    WHERE c.h07 IN ('Y', '1')
),
payment_monthly AS (
    SELECT
        p.p02 AS customer_id,
        date(strftime('%Y-%m-01', p.p06)) AS month_start,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS monthly_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s
      ON s.o01 = p.p03
    WHERE p.p06 < '2006-01-01'
    GROUP BY
        p.p02,
        date(strftime('%Y-%m-01', p.p06))
),
customer_month AS (
    SELECT
        ac.customer_id,
        ac.customer_name,
        ac.city_id,
        ac.city_name,
        ac.country_id,
        ac.country_name,
        m.month_start,
        COALESCE(pm.payment_count, 0) AS payment_count,
        COALESCE(pm.monthly_amount, 0.0) AS monthly_amount,
        COALESCE(pm.staff_count, 0) AS staff_count,
        COALESCE(pm.store_count, 0) AS store_count
    FROM active_customers AS ac
    JOIN months AS m
      ON m.month_start >= ac.registration_month
    LEFT JOIN payment_monthly AS pm
      ON pm.customer_id = ac.customer_id
     AND pm.month_start = m.month_start
),
country_month_median_source AS (
    SELECT
        country_id,
        month_start,
        payment_count,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, month_start
            ORDER BY payment_count
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY country_id, month_start
        ) AS cnt
    FROM customer_month
    WHERE month_start >= '2005-01-01'
      AND month_start < '2006-01-01'
),
country_month_median AS (
    SELECT
        country_id,
        month_start,
        AVG(payment_count * 1.0) AS median_country_payment_count
    FROM country_month_median_source
    WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY
        country_id,
        month_start
),
scored AS (
    SELECT
        cm.*,
        AVG(cm.monthly_amount) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_avg_monthly_amount,
        COUNT(*) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_month_count,
        RANK() OVER (
            PARTITION BY cm.country_id, cm.month_start
            ORDER BY cm.monthly_amount DESC
        ) AS country_month_amount_rank
    FROM customer_month AS cm
)
SELECT
    strftime('%Y-%m', s.month_start) AS payment_month,
    s.customer_id,
    s.customer_name,
    s.country_name,
    s.city_name,
    s.payment_count,
    ROUND(s.monthly_amount, 2) AS monthly_amount,
    ROUND(s.previous_avg_monthly_amount, 2) AS previous_avg_monthly_amount,
    ROUND(s.monthly_amount - s.previous_avg_monthly_amount, 2) AS deviation_from_previous_avg,
    ROUND(s.monthly_amount / NULLIF(s.previous_avg_monthly_amount, 0), 2) AS exceedance_ratio,
    s.staff_count,
    s.store_count,
    ROUND(cmm.median_country_payment_count, 2) AS median_country_payment_count,
    s.country_month_amount_rank
FROM scored AS s
JOIN country_month_median AS cmm
  ON cmm.country_id = s.country_id
 AND cmm.month_start = s.month_start
WHERE s.month_start >= '2005-01-01'
  AND s.month_start < '2006-01-01'
  AND s.previous_month_count > 0
  AND s.previous_avg_monthly_amount > 0
  AND s.monthly_amount >= 3.0 * s.previous_avg_monthly_amount
  AND s.payment_count > cmm.median_country_payment_count
  AND (s.staff_count > 1 OR s.store_count > 1)
ORDER BY
    s.month_start,
    s.country_name,
    s.country_month_amount_rank,
    s.monthly_amount DESC,
    s.customer_id;