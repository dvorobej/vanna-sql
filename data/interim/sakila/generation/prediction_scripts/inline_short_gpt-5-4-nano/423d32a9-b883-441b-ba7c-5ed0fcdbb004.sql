WITH
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    city.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS city ON city.d01 = a.e05
  JOIN cnt ON cnt.c01 = city.d03
),
payments_2005 AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p05 AS amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
monthly AS (
  SELECT
    cg.customer_id,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    p.month_start,
    COUNT(*) AS payment_count,
    SUM(p.amount) AS month_amount,
    COUNT(DISTINCT p.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT p.staff_store_id) AS distinct_store_count
  FROM customer_geo AS cg
  JOIN payments_2005 AS p
    ON p.customer_id = cg.customer_id
  GROUP BY
    cg.customer_id, cg.country_id, cg.country_name, cg.city_name, p.month_start
),
monthly_with_prev AS (
  SELECT
    m.*,
    AVG(m.month_amount) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_month_amount,
    COUNT(*) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM monthly AS m
),
qualified_months AS (
  SELECT
    mwp.*
  FROM monthly_with_prev AS mwp
  WHERE mwp.prev_months_count > 0
    AND mwp.payment_count >= 5
    AND mwp.month_amount >= 2.0 * mwp.avg_prev_month_amount
    AND (mwp.distinct_staff_count >= 2 OR mwp.distinct_store_count >= 2)
),
customers_all_months AS (
  -- клиент должен удовлетворять условиям в каждом месяце 2005 года
  SELECT
    qm.customer_id
  FROM qualified_months AS qm
  GROUP BY qm.customer_id
  HAVING COUNT(DISTINCT qm.month_start) = 12
),
final_months AS (
  SELECT
    qm.*,
    RANK() OVER (
      PARTITION BY qm.country_id, qm.month_start
      ORDER BY qm.month_amount DESC
    ) AS country_month_rank
  FROM qualified_months AS qm
  JOIN customers_all_months AS cam
    ON cam.customer_id = qm.customer_id
)
SELECT
  strftime('%Y-%m', fm.month_start) AS payment_month,
  fm.country_name,
  fm.city_name,
  fm.customer_id,
  fm.avg_prev_month_amount,
  ROUND(fm.month_amount, 2) AS month_amount,
  fm.payment_count,
  ROUND(fm.month_amount - fm.avg_prev_month_amount, 2) AS deviation_from_avg,
  fm.country_month_rank
FROM final_months AS fm
ORDER BY
  fm.month_start,
  fm.country_name,
  fm.country_month_rank,
  fm.customer_id;