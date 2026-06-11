WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS payment_count,
    MAX(p.p05) AS max_payment,
    SUM(CASE WHEN p.p05 > 0 THEN 1 ELSE 0 END) AS payment_positive_count,
    SUM(p.p05) AS month_amount_for_ratio,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT c.h02) AS distinct_store_count
  FROM cus AS c
  JOIN pay AS p
    ON p.p02 = c.h01
  GROUP BY
    c.h01,
    strftime('%Y-%m', p.p06)
),
monthly_customer_metrics AS (
  SELECT
    mc.*,
    (mc.max_payment / NULLIF(mc.month_amount_for_ratio, 0.0)) AS max_payment_share
  FROM monthly_customer AS mc
),
with_history AS (
  SELECT
    mcm.*,
    AVG(month_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount
  FROM monthly_customer_metrics AS mcm
),
qualifying_customers_months AS (
  SELECT
    wh.*
  FROM with_history AS wh
  WHERE wh.prev_avg_month_amount IS NOT NULL
    AND wh.payment_count >= 3
    AND wh.month_amount > 3.0 * wh.prev_avg_month_amount
    AND (wh.distinct_staff_count >= 3 OR wh.distinct_store_count >= 3)
),
customer_enriched AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    c.h02 AS registration_store_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
final AS (
  SELECT
    qcm.month_start,
    qcm.customer_id,
    ce.customer_name,
    ce.country_name,
    ce.city_name,
    qcm.payment_count,
    ROUND(qcm.month_amount, 2) AS month_amount,
    ROUND(qcm.max_payment, 2) AS max_payment,
    ROUND(qcm.max_payment_share, 4) AS max_payment_share,
    qcm.distinct_staff_count,
    qcm.distinct_store_count,
    RANK() OVER (
      PARTITION BY ce.country_name, qcm.month_start
      ORDER BY qcm.month_amount DESC
    ) AS customer_month_rank_in_country
  FROM qualifying_customers_months AS qcm
  JOIN customer_enriched AS ce
    ON ce.customer_id = qcm.customer_id
)
SELECT
  month_start AS month,
  customer_id AS h01,
  customer_name AS h03_h04,
  country_name AS c01_c02,
  city_name AS d02,
  payment_count,
  month_amount,
  max_payment,
  max_payment_share,
  distinct_staff_count AS different_staff_count,
  distinct_store_count AS different_store_count,
  customer_month_rank_in_country
FROM final
ORDER BY
  country_name,
  month_start,
  month_amount DESC,
  customer_id;