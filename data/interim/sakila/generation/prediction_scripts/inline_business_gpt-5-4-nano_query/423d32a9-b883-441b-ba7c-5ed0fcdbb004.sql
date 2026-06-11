WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ci.d01 AS city_id,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
payments_2005 AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_monthly AS (
  SELECT
    pg.customer_id,
    pg.month_start,
    COUNT(*) AS payment_count,
    SUM(pg.payment_amount) AS month_sum,
    AVG(pg.payment_amount) AS avg_payment_amount,
    COUNT(DISTINCT pg.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pg.staff_store_id) AS distinct_store_count
  FROM payments_2005 AS pg
  GROUP BY
    pg.customer_id,
    pg.month_start
),
customer_monthly_with_prev AS (
  SELECT
    cm.*,
    AVG(cm.month_sum) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_sum
  FROM customer_monthly AS cm
),
qualified_months AS (
  SELECT
    cmw.*,
    (cmw.month_sum - cmw.prev_avg_month_sum) AS deviation_from_prev_avg,
    CASE
      WHEN cmw.prev_avg_month_sum > 0 THEN (cmw.month_sum / cmw.prev_avg_month_sum)
    END AS ratio_to_prev_avg
  FROM customer_monthly_with_prev AS cmw
  WHERE cmw.prev_avg_month_sum IS NOT NULL
    AND cmw.payment_count >= 5
    AND cmw.month_sum >= 2.0 * cmw.prev_avg_month_sum
    AND (cmw.distinct_staff_count >= 2 OR cmw.distinct_store_count >= 2)
),
all_months_2005_count AS (
  SELECT 12 AS months_in_year
),
clients_with_all_months AS (
  SELECT
    qm.customer_id
  FROM qualified_months AS qm
  GROUP BY qm.customer_id
  HAVING COUNT(DISTINCT qm.month_start) = (SELECT months_in_year FROM all_months_2005_count)
),
ranked_deviation AS (
  SELECT
    qm.*,
    RANK() OVER (
      PARTITION BY cg.country_id, qm.month_start
      ORDER BY qm.deviation_from_prev_avg DESC
    ) AS customer_deviation_rank_in_country
  FROM qualified_months AS qm
  JOIN customer_geo AS cg ON cg.customer_id = qm.customer_id
  JOIN clients_with_all_months AS cwa ON cwa.customer_id = qm.customer_id
)
SELECT
  strftime('%Y-%m', rd.month_start) AS payment_month,
  cg.country_name AS country,
  cg.city_name AS city,
  ROUND(rd.month_sum, 2) AS month_sum,
  rd.payment_count,
  ROUND(rd.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  rd.customer_deviation_rank_in_country
FROM ranked_deviation AS rd
JOIN customer_geo AS cg ON cg.customer_id = rd.customer_id
ORDER BY
  rd.month_start,
  cg.country_name,
  customer_deviation_rank_in_country,
  rd.customer_id;