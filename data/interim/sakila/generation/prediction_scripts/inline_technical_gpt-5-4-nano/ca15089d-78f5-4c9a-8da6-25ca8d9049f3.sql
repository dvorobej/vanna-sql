WITH month_calc AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS monthly_amount,
    COUNT(*) AS payment_count,
    MAX(p.p05) AS max_payment,
    SUM(CASE WHEN p.p05 = (SELECT MAX(p2.p05) FROM pay p2 WHERE p2.p02 = p.p02 AND strftime('%Y-%m', p2.p06) = strftime('%Y-%m', p.p06)) THEN 1 ELSE 0 END) AS max_payment_occurrences,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT c.h02) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
month_enriched AS (
  SELECT
    mc.*,
    (mc.max_payment / NULLIF(mc.monthly_amount, 0)) AS max_payment_share,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_amount
  FROM month_calc AS mc
),
qualified_months AS (
  SELECT
    me.*
  FROM month_enriched AS me
  WHERE me.prev_avg_monthly_amount IS NOT NULL
    AND me.monthly_amount >= 3.0 * me.prev_avg_monthly_amount
    AND me.payment_count >= 3
    AND (me.distinct_staff_count >= 3 OR me.distinct_store_count >= 3)
),
addr_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country_name,
    city.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = city.d03
),
monthly_detail AS (
  SELECT
    qm.customer_id,
    ag.customer_name,
    ag.country_name,
    ag.city_name,
    qm.month_start,
    qm.payment_count,
    qm.monthly_amount,
    qm.max_payment,
    qm.max_payment_share,
    qm.distinct_staff_count,
    qm.distinct_store_count
  FROM qualified_months AS qm
  JOIN addr_geo AS ag
    ON ag.customer_id = qm.customer_id
)
SELECT
  md.country_name,
  md.city_name,
  md.month_start AS month,
  md.customer_name AS h03_h04,
  md.payment_count,
  ROUND(md.monthly_amount, 2) AS monthly_amount,
  ROUND(md.max_payment, 2) AS max_payment,
  ROUND(md.max_payment_share, 4) AS max_payment_share,
  md.distinct_staff_count AS different_staff_count,
  md.distinct_store_count AS different_store_count,
  RANK() OVER (
    PARTITION BY ag.country_name, md.month_start
    ORDER BY md.monthly_amount DESC
  ) AS customer_rank_in_country_month
FROM monthly_detail AS md
JOIN addr_geo AS ag
  ON ag.customer_id = md.customer_id
ORDER BY
  md.country_name,
  md.month_start,
  md.monthly_amount DESC,
  md.customer_id;