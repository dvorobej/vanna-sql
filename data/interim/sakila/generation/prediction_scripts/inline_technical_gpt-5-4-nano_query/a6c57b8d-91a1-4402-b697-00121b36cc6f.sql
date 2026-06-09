SELECT country_id FROM customer_geo WHERE customer_id = mcwp.customer_id LIMIT 1)
    ) AS country_decile_placeholder
  FROM monthly_customer_with_personal AS mcwp
),
ranked AS (
  SELECT
    mcwp.customer_id,
    cg.country,
    cg.city,
    mcwp.month_start,
    mcwp.payment_count,
    mcwp.month_sum,
    mcwp.personal_avg_month_sum,
    (mcwp.month_sum - mcwp.personal_avg_month_sum) AS deviation_from_personal_avg,
    RANK() OVER (
      PARTITION BY cg.country, mcwp.month_start
      ORDER BY mcwp.month_sum DESC
    ) AS country_month_rank,
    COUNT(*) OVER (
      PARTITION BY cg.country, mcwp.month_start
    ) AS country_month_customer_count
  FROM monthly_customer_with_personal AS mcwp
  JOIN customer_geo AS cg
    ON cg.customer_id = mcwp.customer_id
),
top_10pct AS (
  SELECT
    r.*,
    CAST(r.country_month_customer_count * 0.10 AS INTEGER) AS top10_floor_cnt
  FROM ranked AS r
),
last_top_staff AS (
  SELECT
    p.customer_id,
    date(p.payment_dt, 'start of month') AS month_start,
    p.staff_id,
    SUM(p.amount) AS staff_month_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, date(p.payment_dt, 'start of month')
      ORDER BY SUM(p.amount) DESC, p.staff_id
    ) AS rn
  FROM payments_2005 AS p
  GROUP BY
    p.customer_id,
    date(p.payment_dt, 'start of month'),
    p.staff_id
)
SELECT
  t.customer_id,
  t.country,
  t.city,
  strftime('%Y-%m', t.month_start) AS payment_month,
  ROUND(t.month_sum, 2) AS month_sum,
  t.payment_count,
  ROUND(t.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  t.country_month_rank AS country_month_customer_rank,
  s.o01 AS top_staff_id,
  s.o02 AS top_staff_first_name,
  s.o03 AS top_staff_last_name,
  ROUND(lt.staff_month_sum, 2) AS top_staff_month_sum
FROM top_10pct AS t
JOIN last_top_staff AS lt
  ON lt.customer_id = t.customer_id
 AND lt.month_start = t.month_start
 AND lt.rn = 1
JOIN stf AS s
  ON s.o01 = lt.staff_id
WHERE
  t.personal_avg_month_sum IS NOT NULL
  AND t.personal_avg_month_sum > 0
  AND t.month_sum > 2.0 * t.personal_avg_month_sum
  AND t.country_month_rank <=
      CASE
        WHEN t.top10_floor_cnt < 1 THEN 1
        ELSE t.top10_floor_cnt
      END
ORDER BY
  t.country,
  t.month_start,
  t.month_sum DESC,
  t.customer_id;