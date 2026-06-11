WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS payment_sum,
    AVG(p.p05) AS avg_check,
    COUNT(DISTINCT date(p.p06)) AS active_days_count
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_monthly AS (
  SELECT
    m.*,
    AVG(m.payment_sum) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS customer_prev_avg_month_sum,
    LAG(m.payment_sum) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.month_start
    ) AS prev_month_sum
  FROM monthly AS m
),
country_monthly AS (
  SELECT
    cm.month_start,
    c.h02 AS customer_store_id,
    co.c02 AS country_name,
    co.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
  WHERE c.h07 IN ('Y','y') OR c.h07 IS NULL
  GROUP BY
    cm.month_start,
    c.h02,
    co.c02,
    co.c01
),
country_monthly_stats AS (
  SELECT
    m.month_start,
    co.c01 AS country_id,
    AVG(m.payment_sum) AS country_avg_month_payment_sum
  FROM monthly AS m
  JOIN cus AS c ON c.h01 = m.customer_id
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
  GROUP BY
    m.month_start,
    co.c01
),
monthly_enriched AS (
  SELECT
    cm.customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    co.c01 AS country_id,
    co.c02 AS country_name,
    cm.month_start,
    cm.payment_count,
    cm.payment_sum,
    cm.avg_check,
    cm.active_days_count,
    cm.prev_month_sum,
    cms.country_avg_month_payment_sum,
    CASE
      WHEN cm.prev_month_sum IS NOT NULL AND cm.prev_month_sum <> 0
        THEN cm.payment_sum / cm.prev_month_sum
      ELSE NULL
    END AS growth_vs_prev_month_ratio,
    CASE
      WHEN cms.country_avg_month_payment_sum IS NOT NULL AND cms.country_avg_month_payment_sum <> 0
        THEN cm.payment_sum / cms.country_avg_month_payment_sum
      ELSE NULL
    END AS ratio_vs_country_avg
  FROM customer_monthly AS cm
  JOIN cus AS c ON c.h01 = cm.customer_id
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
  JOIN country_monthly_stats AS cms
    ON cms.month_start = cm.month_start
   AND cms.country_id = co.c01
),
ranked_in_country AS (
  SELECT
    me.*,
    RANK() OVER (
      PARTITION BY me.country_id, me.month_start
      ORDER BY me.payment_sum DESC
    ) AS customer_country_payment_rank
  FROM monthly_enriched AS me
),
top_staff_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    RANK() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC
    ) AS staff_sum_rank
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
top_staff_month_pick AS (
  SELECT
    t.customer_id,
    t.month_start,
    t.staff_id,
    t.staff_payment_sum
  FROM top_staff_month AS t
  WHERE t.staff_sum_rank = 1
),
customer_store_staff AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    s.o01 AS staff_id,
    s.o02 || ' ' || s.o03 AS staff_name
  FROM cus AS c
  JOIN stf AS s ON s.o01 = s.o01
)
SELECT
  r.customer_id,
  r.customer_first_name || ' ' || r.customer_last_name AS customer_name,
  r.country_name AS country,
  r.month_start AS month,
  r.payment_count,
  ROUND(r.payment_sum, 2) AS payment_sum,
  ROUND(r.avg_check, 2) AS avg_check,
  r.active_days_count AS active_days_count,
  r.prev_month_sum,
  ROUND(r.growth_vs_prev_month_ratio, 4) AS growth_vs_prev_month_ratio,
  ROUND(r.country_avg_month_payment_sum, 2) AS country_avg_month_payment_sum,
  ROUND(r.ratio_vs_country_avg, 4) AS ratio_vs_country_avg,
  r.customer_country_payment_rank AS country_payment_rank,
  c.h02 AS store_id,
  ts.staff_id,
  ts_staff.o02 || ' ' || ts_staff.o03 AS top_staff_name,
  ROUND(ts.staff_payment_sum, 2) AS top_staff_payment_sum
FROM ranked_in_country AS r
JOIN cus AS c
  ON c.h01 = r.customer_id
JOIN top_staff_month_pick AS ts
  ON ts.customer_id = r.customer_id
 AND ts.month_start = r.month_start
JOIN stf AS ts_staff
  ON ts_staff.o01 = ts.staff_id
WHERE
  (
    r.prev_month_sum IS NOT NULL
    AND r.prev_month_sum <> 0
    AND r.payment_sum >= 3.0 * r.prev_month_sum
  )
  OR (
    r.country_avg_month_payment_sum IS NOT NULL
    AND r.country_avg_month_payment_sum <> 0
    AND r.payment_sum > 2.0 * r.country_avg_month_payment_sum
  )
ORDER BY
  r.month_start,
  r.country_name,
  r.customer_country_payment_rank,
  r.payment_sum DESC;