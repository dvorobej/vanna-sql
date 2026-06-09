SELECT COUNT(DISTINCT date(p2.p06))
      FROM pay AS p2
      WHERE p2.p02 = wp.customer_id
        AND date(p2.p06, 'start of month') = wp.month_start
    ) AS active_days_count,
    wp.prev_month_amount,
    cma.country_avg_month_amount,
    CASE
      WHEN wp.prev_month_amount IS NULL OR wp.prev_month_amount = 0 THEN NULL
      ELSE wp.month_amount / wp.prev_month_amount
    END AS ratio_to_prev_month,
    CASE
      WHEN cma.country_avg_month_amount IS NULL OR cma.country_avg_month_amount = 0 THEN NULL
      ELSE wp.month_amount / cma.country_avg_month_amount
    END AS ratio_to_country_avg
  FROM with_prev_month wp
  JOIN country_month_avg cma
    ON cma.country_name = wp.country_name
   AND cma.month_start = wp.month_start
),
month_top_staff AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    SUM(p.p05) AS staff_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03,
    s.o07
),
rank_in_country AS (
  SELECT
    cms.*,
    RANK() OVER (
      PARTITION BY cms.country_name, cms.month_start
      ORDER BY cms.month_amount DESC
    ) AS country_month_payment_rank
  FROM client_month_scored cms
)
SELECT
  rc.customer_id,
  rc.customer_name,
  rc.country_name AS country,
  rc.month_start AS month,
  rc.payment_count,
  rc.month_amount,
  rc.avg_check,
  rc.active_days_count,
  rc.prev_month_amount,
  rc.country_avg_month_amount,
  rc.ratio_to_prev_month,
  rc.ratio_to_country_avg,
  rc.country_month_payment_rank,
  c.h02 AS customer_home_store_id,
  ts.staff_store_id AS store_of_top_staff,
  ts.staff_id AS top_staff_id,
  s.o02 || ' ' || s.o03 AS top_staff_name
FROM rank_in_country rc
JOIN cus AS c
  ON c.h01 = rc.customer_id
LEFT JOIN month_top_staff ts
  ON ts.customer_id = rc.customer_id
 AND ts.month_start = rc.month_start
 AND ts.rn = 1
LEFT JOIN stf AS s
  ON s.o01 = ts.staff_id
WHERE
  (
    rc.prev_month_amount IS NOT NULL
    AND rc.prev_month_amount <> 0
    AND rc.month_amount / rc.prev_month_amount >= 3
  )
  OR
  (
    rc.country_avg_month_amount IS NOT NULL
    AND rc.country_avg_month_amount <> 0
    AND rc.month_amount / rc.country_avg_month_amount > 2
  )
ORDER BY
  rc.month_start,
  rc.country_name,
  rc.country_month_payment_rank,
  rc.customer_id;