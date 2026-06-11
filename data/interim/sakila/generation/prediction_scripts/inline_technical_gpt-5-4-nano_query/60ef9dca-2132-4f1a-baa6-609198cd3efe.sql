WITH months(month_start) AS (
  SELECT date('2005-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
customer_store_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    c.h06 AS address_id,
    ci.d02 AS city_name,
    co.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    cs.customer_id,
    cs.store_id,
    cs.city_name,
    cs.country_name,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_sum
  FROM months AS m
  JOIN customer_store_geo AS cs
  LEFT JOIN pay AS p
    ON p.p02 = cs.customer_id
   AND date(p.p06, 'start of month') = m.month_start
  GROUP BY
    cs.customer_id,
    cs.store_id,
    cs.city_name,
    cs.country_name,
    date(p.p06, 'start of month')
),
customer_year_avg AS (
  SELECT
    customer_id,
    store_id,
    city_name,
    country_name,
    AVG(month_sum) AS personal_avg_month_sum
  FROM monthly_customer
  GROUP BY customer_id, store_id, city_name, country_name
),
monthly_rank_in_store AS (
  SELECT
    mc.*,
    cya.personal_avg_month_sum,
    (mc.month_sum - cya.personal_avg_month_sum) AS deviation_from_personal_avg,
    RANK() OVER (
      PARTITION BY mc.store_id, mc.month_start
      ORDER BY mc.month_sum DESC
    ) AS store_month_rank
  FROM monthly_customer AS mc
  JOIN customer_year_avg AS cya
    ON cya.customer_id = mc.customer_id
   AND cya.store_id = mc.store_id
),
store_month_stats AS (
  SELECT
    store_id,
    month_start,
    COUNT(*) AS store_customers_count
  FROM monthly_rank_in_store
  GROUP BY store_id, month_start
),
monthly_with_top5pct AS (
  SELECT
    mr.*,
    SMS.store_customers_count,
    CASE
      WHEN SMS.store_customers_count IS NOT NULL AND SMS.store_customers_count > 0
      THEN CAST(mr.store_month_rank AS REAL) / SMS.store_customers_count
    END AS rank_fraction
  FROM monthly_rank_in_store AS mr
  JOIN store_month_stats AS SMS
    ON SMS.store_id = mr.store_id
   AND SMS.month_start = mr.month_start
),
last_staff_by_customer_month AS (
  SELECT
    p.p02 AS customer_id,
    p.p06_month AS dummy,
    p.p03 AS staff_id
  FROM (
    SELECT
      pay.p02,
      date(pay.p06, 'start of month') AS p06_month,
      pay.p03,
      ROW_NUMBER() OVER (
        PARTITION BY pay.p02, date(pay.p06, 'start of month')
        ORDER BY pay.p06 DESC, pay.p01 DESC
      ) AS rn
    FROM pay
  ) AS p
  WHERE p.rn = 1
),
last_staff AS (
  SELECT
    x.p02 AS customer_id,
    x.p06_month AS month_start,
    x.p03 AS staff_id
  FROM (
    SELECT
      pay.p02,
      date(pay.p06, 'start of month') AS p06_month,
      pay.p03,
      ROW_NUMBER() OVER (
        PARTITION BY pay.p02, date(pay.p06, 'start of month')
        ORDER BY pay.p06 DESC, pay.p01 DESC
      ) AS rn
    FROM pay
  ) AS x
  WHERE x.rn = 1
),
final_candidates AS (
  SELECT
    mwt.*,
    COUNT(*) OVER (PARTITION BY mwt.customer_id) AS months_total_in_year,
    SUM(CASE WHEN mwt.month_sum > mwt.personal_avg_month_sum * 2 THEN 1 ELSE 0 END)
      OVER (PARTITION BY mwt.customer_id) AS months_meet_personal_rule,
    SUM(CASE WHEN (mwt.rank_fraction IS NOT NULL AND mwt.rank_fraction <= 0.05) THEN 1 ELSE 0 END)
      OVER (PARTITION BY mwt.customer_id) AS months_meet_top5_rule
  FROM monthly_with_top5pct AS mwt
),
qualifying_customers AS (
  SELECT DISTINCT customer_id
  FROM final_candidates
  WHERE months_meet_personal_rule = 12
    AND months_meet_top5_rule = 12
)
SELECT
  f.customer_id,
  f.store_id AS registration_store_id,
  f.city_name,
  f.country_name,
  strftime('%Y-%m', f.month_start) AS month,
  ROUND(f.month_sum, 2) AS month_sum,
  f.payment_count,
  ROUND(f.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  f.store_month_rank AS store_month_rank,
  ls.staff_id AS last_staff_id,
  st.o02 || ' ' || st.o03 AS last_staff_name
FROM final_candidates AS f
JOIN qualifying_customers AS qc
  ON qc.customer_id = f.customer_id
LEFT JOIN last_staff AS ls
  ON ls.customer_id = f.customer_id
 AND ls.month_start = f.month_start
LEFT JOIN stf AS st
  ON st.o01 = ls.staff_id
WHERE f.month_sum > f.personal_avg_month_sum * 2
  AND f.rank_fraction IS NOT NULL
  AND f.rank_fraction <= 0.05
ORDER BY
  f.customer_id,
  f.month_start;