WITH months_2005 AS (
  SELECT strftime('%Y-%m', p.p06) AS ym,
         date(p.p06, 'start of month') AS month_start
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY 1,2
),
pay_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS ym,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    c.h02 AS home_store_id,
    a.e05 AS city_id,
    ct.d03 AS country_id
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = a.e05
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    pb.country_id,
    pb.city_id,
    pb.month_start,
    pb.ym,
    COUNT(*) AS payment_count,
    SUM(pb.payment_amount) AS payment_sum
  FROM pay_base pb
  GROUP BY
    pb.customer_id,
    pb.country_id,
    pb.city_id,
    pb.month_start,
    pb.ym
),
customer_avg AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id
    ) AS personal_avg_monthly_payment_sum
  FROM monthly_customer mc
),
country_p90 AS (
  SELECT
    cc.country_id,
    cc.month_start,
    cc.ym,
    cc.payment_sum,
    DENSE_RANK() OVER (
      PARTITION BY cc.country_id, cc.month_start
      ORDER BY cc.payment_sum
    ) AS dr_asc,
    COUNT(*) OVER (
      PARTITION BY cc.country_id, cc.month_start
    ) AS cnt_in_month
  FROM monthly_customer cc
),
country_p90_threshold AS (
  SELECT
    country_id,
    month_start,
    ym,
    MAX(payment_sum) AS p90_payment_sum
  FROM (
    SELECT
      c.country_id,
      c.month_start,
      c.ym,
      c.payment_sum,
      cnt_in_month,
      dr_asc,
      CASE
        WHEN cnt_in_month <= 1 THEN 0
        ELSE CAST(0.90 * (cnt_in_month - 1) AS INTEGER)
      END AS cutoff_pos
    FROM country_p90 c
  ) t
  WHERE dr_asc >= (
    SELECT cutoff_pos + 1
  )
  GROUP BY country_id, month_start, ym
),
flagged AS (
  SELECT
    ca.customer_id AS h01,
    ca.country_id,
    ca.city_id,
    ca.month_start,
    ca.ym,
    ca.payment_sum,
    ca.payment_count,
    (ca.payment_sum - ca.personal_avg_monthly_payment_sum) AS delta_from_personal_avg,
    (1.0 * ca.payment_sum / NULLIF(ca.personal_avg_monthly_payment_sum, 0)) AS personal_vs_avg_ratio,
    RANK() OVER (
      PARTITION BY ca.country_id, ca.month_start
      ORDER BY ca.payment_sum DESC
    ) AS customer_rank_in_country,
    ca.personal_avg_monthly_payment_sum
  FROM customer_avg ca
  JOIN country_p90_threshold th
    ON th.country_id = ca.country_id
   AND th.month_start = ca.month_start
  WHERE ca.personal_avg_monthly_payment_sum IS NOT NULL
    AND ca.personal_avg_monthly_payment_sum > 0
    AND ca.payment_sum > 2.0 * ca.personal_avg_monthly_payment_sum
    AND ca.payment_sum > th.p90_payment_sum
),
staff_top AS (
  SELECT
    pb.customer_id,
    pb.country_id,
    pb.city_id,
    pb.month_start,
    pb.ym,
    pb.staff_id,
    SUM(pb.payment_amount) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY pb.customer_id, pb.month_start
      ORDER BY SUM(pb.payment_amount) DESC
    ) AS rn_staff
  FROM pay_base pb
  GROUP BY
    pb.customer_id,
    pb.country_id,
    pb.city_id,
    pb.month_start,
    pb.ym,
    pb.staff_id
)
SELECT
  f.h01,
  co.c02 AS country_name,
  ci.d02 AS city_name,
  f.ym AS month,
  ROUND(f.payment_sum, 2) AS payment_sum,
  f.payment_count,
  ROUND(f.delta_from_personal_avg, 2) AS deviation_from_personal_avg,
  f.customer_rank_in_country AS rank_in_country,
  st.staff_id AS top_staff_id,
  st.staff_payment_sum AS top_staff_payment_sum
FROM flagged f
JOIN cnt co
  ON co.c01 = f.country_id
JOIN cty ci
  ON ci.d01 = f.city_id
JOIN staff_top st
  ON st.customer_id = f.h01
 AND st.month_start = f.month_start
 AND st.rn_staff = 1
ORDER BY
  co.c02,
  f.month,
  f.payment_sum DESC,
  f.h01;