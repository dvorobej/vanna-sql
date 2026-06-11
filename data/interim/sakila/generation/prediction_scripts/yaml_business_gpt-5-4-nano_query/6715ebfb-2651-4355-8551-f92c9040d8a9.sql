WITH RECURSIVE months(month_start) AS (
  SELECT date('2004-11-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2006-01-01')
),
payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS store_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
customer_month AS (
  SELECT
    pe.customer_id,
    pe.store_id,
    pe.country_name,
    pe.city_name,
    pe.month_start,
    SUM(pe.payment_amount) AS month_total_amount,
    COUNT(*) AS month_payment_count
  FROM payment_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.store_id,
    pe.country_name,
    pe.city_name,
    pe.month_start
),
customer_history AS (
  SELECT
    cm.*,
    AVG(cm.month_total_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_avg_month_amount,
    COUNT(cm.month_total_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_months_cnt,
    AVG(cm.month_payment_count) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_hist_avg_month_payment_count
  FROM customer_month AS cm
),
country_month_median_paycount AS (
  SELECT
    cm.*,
    ROW_NUMBER() OVER (
      PARTITION BY cm.country_name, cm.month_start
      ORDER BY cm.month_payment_count
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY cm.country_name, cm.month_start
    ) AS cnt_in_country_month
  FROM customer_month AS cm
),
country_month_median_value AS (
  SELECT
    country_name,
    month_start,
    AVG(CASE
          WHEN rn IN (CAST((cnt_in_country_month + 1) / 2 AS INTEGER),
                     CAST((cnt_in_country_month + 2) / 2 AS INTEGER))
          THEN month_payment_count
        END
    ) AS median_month_payment_count
  FROM country_month_median_paycount
  GROUP BY country_name, month_start
),
suspicious_cases AS (
  SELECT
    ch.customer_id,
    ch.store_id,
    ch.country_name,
    ch.city_name,
    ch.month_start,
    ch.month_total_amount,
    ch.month_payment_count,
    ch.personal_hist_avg_month_amount,
    cmm.median_month_payment_count
  FROM customer_history AS ch
  JOIN country_month_median_value AS cmm
    ON cmm.country_name = ch.country_name
   AND cmm.month_start = ch.month_start
  WHERE ch.personal_hist_month_amount IS NULL
),
monthly_staff_max AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    MAX(pe.payment_amount) AS max_single_payment_amount
  FROM payment_enriched AS pe
  GROUP BY pe.customer_id, pe.month_start
),
action_new_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS total_amount_in_month,
    SUM(
      CASE
        WHEN c2.g02 IN ('Action', 'New') THEN p.p05
        ELSE 0
      END
    ) AS action_new_amount
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat AS c2
    ON c2.g01 = fc.l02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
country_suspicious_rank AS (
  SELECT
    cm.country_name,
    cm.month_start,
    cm.customer_id,
    SUM(cm.month_total_amount) AS suspicious_total_amount,
    DENSE_RANK() OVER (
      PARTITION BY cm.country_name, cm.month_start
      ORDER BY SUM(cm.month_total_amount) DESC
    ) AS country_month_customer_rank
  FROM customer_month AS cm
  GROUP BY cm.country_name, cm.month_start, cm.customer_id
)
SELECT
  sc.country_name,
  sc.city_name,
  sc.store_id AS store_id,
  sc.month_payment_count AS payment_count,
  ROUND(sc.month_total_amount, 2) AS month_total_amount,
  ROUND(ms.max_single_payment_amount, 2) AS max_single_payment_amount,
  ROUND(
    1.0 * an.action_new_amount / NULLIF(an.total_amount_in_month, 0),
    4
  ) AS action_new_lease_share,
  csr.country_month_customer_rank AS customer_country_rank
FROM suspicious_cases AS sc
JOIN monthly_staff_max AS ms
  ON ms.customer_id = sc.customer_id
 AND ms.month_start = sc.month_start
LEFT JOIN action_new_share AS an
  ON an.customer_id = sc.customer_id
 AND an.month_start = sc.month_start
JOIN country_suspicious_rank AS csr
  ON csr.country_name = sc.country_name
 AND csr.month_start = sc.month_start
 AND csr.customer_id = sc.customer_id
ORDER BY
  sc.month_start,
  sc.country_name,
  csr.country_month_customer_rank,
  sc.customer_id;