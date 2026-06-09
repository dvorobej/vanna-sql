WITH monthly_base AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    SUM(p.p05) AS month_sum,
    COUNT(p.p01) AS payment_count,
    MAX(p.p05) AS max_payment,
    SUM(p.p05) * 1.0 AS month_sum_real,
    MAX(p.p05) * 1.0 / SUM(p.p05) AS max_payment_share,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  LEFT JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
  SELECT
    mb.*,
    AVG(month_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_sum
  FROM monthly_base AS mb
),
qualifying_months AS (
  SELECT
    mwh.*
  FROM monthly_with_history AS mwh
  WHERE mwh.prev_avg_month_sum IS NOT NULL
    AND mwh.payment_count >= 3
    AND mwh.month_sum > 3.0 * mwh.prev_avg_month_sum
    AND (mwh.distinct_staff_count >= 3 OR mwh.distinct_store_count >= 3)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03,
    c.h04,
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
monthly_final AS (
  SELECT
    qm.customer_id,
    cg.h03 || ' ' || cg.h04 AS month_customer_name,
    cg.country_name,
    cg.city_name,
    qm.month_start,
    qm.payment_count,
    qm.month_sum,
    qm.max_payment,
    qm.max_payment_share,
    qm.distinct_staff_count,
    qm.distinct_store_count,
    RANK() OVER (
      PARTITION BY cg.country_name, qm.month_start
      ORDER BY qm.month_sum DESC
    ) AS customer_month_rank
  FROM qualifying_months AS qm
  JOIN customer_geo AS cg
    ON cg.customer_id = qm.customer_id
)
SELECT
  customer_id AS h01,
  month_customer_name AS h03_h04,
  country_name AS c02,
  city_name AS d02,
  month_start,
  payment_count,
  ROUND(month_sum, 2) AS month_sum,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(max_payment_share, 4) AS max_payment_share,
  distinct_staff_count,
  distinct_store_count,
  customer_month_rank
FROM monthly_final
ORDER BY
  country_name,
  month_start,
  month_sum DESC,
  h01;