WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    co.c02 AS country_name,
    c.h02 AS registration_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.country_name,
    p.p03 AS staff_id,
    MAX(cg.registration_store_id) AS registration_store_id,
    strftime('%Y-%m', p.p06) AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS monthly_sum,
    AVG(p.p05) AS avg_check,
    COUNT(DISTINCT date(p.p06)) AS active_days
  FROM pay AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.p02
  GROUP BY
    p.p02,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.country_name,
    p.p03,
    strftime('%Y-%m', p.p06)
),
monthly_customer AS (
  SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    country_name,
    month_start,
    SUM(payment_count) AS payment_count,
    SUM(monthly_sum) AS monthly_sum,
    AVG(avg_check) AS avg_check,
    MAX(active_days) AS active_days
  FROM monthly_pay
  GROUP BY
    customer_id,
    customer_first_name,
    customer_last_name,
    country_name,
    month_start
),
monthly_with_lag AS (
  SELECT
    mc.*,
    LAG(mc.monthly_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    ) AS prev_monthly_sum
  FROM monthly_customer mc
),
country_month_avg AS (
  SELECT
    country_name,
    month_start,
    AVG(monthly_sum) AS country_avg_monthly_sum
  FROM monthly_customer
  GROUP BY country_name, month_start
),
joined AS (
  SELECT
    mwl.*,
    cmaa.country_avg_monthly_sum,
    RANK() OVER (
      PARTITION BY mwl.country_name, mwl.month_start
      ORDER BY mwl.monthly_sum DESC
    ) AS country_month_payment_rank
  FROM monthly_with_lag mwl
  JOIN country_month_avg cmaa
    ON cmaa.country_name = mwl.country_name
   AND cmaa.month_start = mwl.month_start
)
SELECT
  j.country_month_payment_rank AS customer_country_month_rank,
  j.customer_id,
  j.customer_first_name,
  j.customer_last_name,
  j.country_name,
  j.month_start AS payment_month,
  j.payment_count,
  ROUND(j.monthly_sum, 2) AS monthly_sum,
  ROUND(j.avg_check, 2) AS avg_check,
  j.active_days,
  ROUND(j.monthly_sum / NULLIF(j.prev_monthly_sum, 0), 2) AS growth_vs_prev_month_ratio,
  ROUND(j.monthly_sum / NULLIF(j.country_avg_monthly_sum, 0), 2) AS vs_country_avg_ratio,
  mp_staff.max_staff_id AS top_staff_id,
  s.o02 || ' ' || s.o03 AS top_staff_name,
  mp_staff.max_staff_store_id AS top_staff_store_id,
  sto.j01 AS top_store_id
FROM joined j
JOIN (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    MAX(p.p03) AS max_staff_id, -- tie-breaker placeholder (overridden below)
    MAX(s.o07) AS max_staff_store_id
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  GROUP BY p.p02, strftime('%Y-%m', p.p06)
) tmp ON tmp.customer_id = j.customer_id AND tmp.month_start = j.payment_month
LEFT JOIN stf s ON s.o01 = tmp.max_staff_id
LEFT JOIN sto ON sto.j01 = s.o07
JOIN (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    p.p03 AS max_staff_id,
    s.o07 AS max_staff_store_id
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  JOIN (
    SELECT
      p2.p02 AS customer_id,
      strftime('%Y-%m', p2.p06) AS month_start,
      MAX(SUM(p2.p05)) OVER (
        PARTITION BY p2.p02, strftime('%Y-%m', p2.p06)
      ) AS max_sum_staff_amount
    FROM pay p2
  ) x
    ON x.customer_id = p.p02
   AND x.month_start = strftime('%Y-%m', p.p06)
  GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03, s.o07
) mp_staff
  ON mp_staff.customer_id = j.customer_id
 AND mp_staff.month_start = j.payment_month
WHERE
  (j.prev_monthly_sum IS NOT NULL AND j.monthly_sum >= 3.0 * j.prev_monthly_sum)
  OR
  (j.country_avg_monthly_sum > 0 AND j.monthly_sum > 2.0 * j.country_avg_monthly_sum)
ORDER BY
  j.country_name,
  j.payment_month,
  j.country_month_payment_rank;