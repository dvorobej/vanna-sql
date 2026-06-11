WITH payments AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_date,
    strftime('%Y-%m', p.p06) AS month_start,
    c.h02 AS customer_store_id,
    c.h06 AS customer_address_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
),
cust_country AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = city.d03
),
base AS (
  SELECT
    pay.customer_id,
    pay.month_start,
    pay.payment_amount,
    pay.staff_id,
    pay.customer_store_id,
    cc.country_id
  FROM payments AS pay
  JOIN cust_country AS cc
    ON cc.customer_id = pay.customer_id
),
monthly_customer AS (
  SELECT
    b.customer_id,
    b.month_start,
    SUM(b.payment_amount) AS month_sum,
    COUNT(*) AS month_payment_count,
    AVG(b.payment_amount) AS month_avg_payment,
    COUNT(DISTINCT b.staff_id) AS distinct_staff_count,
    SUM(CASE WHEN st.o07 <> b.customer_store_id THEN 1 ELSE 0 END) AS off_store_payment_count,
    1.0 * SUM(CASE WHEN st.o07 <> b.customer_store_id THEN 1 ELSE 0 END) / COUNT(*) AS off_store_payment_share
  FROM base AS b
  JOIN stf AS st
    ON st.o01 = b.staff_id
  GROUP BY
    b.customer_id,
    b.month_start
),
monthly_customer_with_history AS (
  SELECT
    mc.*,
    cc.country_id,
    AVG(mc.month_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_2_months
  FROM monthly_customer AS mc
  JOIN cust_country AS cc
    ON cc.customer_id = mc.customer_id
),
country_month_ord AS (
  SELECT
    m.month_start,
    m.country_id,
    m.customer_id,
    m.month_sum,
    COUNT(*) OVER (PARTITION BY m.country_id, m.month_start) AS group_count,
    ROW_NUMBER() OVER (
      PARTITION BY m.country_id, m.month_start
      ORDER BY m.month_sum
    ) AS rn
  FROM monthly_customer_with_history AS m
  WHERE m.country_id IS NOT NULL
),
country_month_p95 AS (
  SELECT
    country_id,
    month_start,
    /* линейная интерполяция позиции 95% */
    (
      MAX(CASE WHEN rn = CAST((0.95 * group_count + 0.5) AS INTEGER) THEN month_sum END) +
      ( (0.95 * group_count + 0.5) - CAST((0.95 * group_count + 0.5) AS INTEGER) )
      * (
          MAX(CASE WHEN rn = CAST((0.95 * group_count + 0.5) AS INTEGER) + 1 THEN month_sum END)
          - MAX(CASE WHEN rn = CAST((0.95 * group_count + 0.5) AS INTEGER) THEN month_sum END)
        )
    ) AS p95_month_sum
  FROM (
    SELECT
      *,
      MAX(group_count) OVER (PARTITION BY country_id, month_start) AS group_count_max
    FROM country_month_ord
  ) t
  GROUP BY country_id, month_start
),
country_month_metrics AS (
  SELECT
    mcwh.*,
    cm.p95_month_sum,
    RANK() OVER (
      PARTITION BY mcwh.country_id, mcwh.month_start
      ORDER BY mcwh.month_sum DESC
    ) AS customer_country_month_rank
  FROM monthly_customer_with_history AS mcwh
  JOIN country_month_p95 AS cm
    ON cm.country_id = mcwh.country_id
   AND cm.month_start = mcwh.month_start
),
final_filtered AS (
  SELECT
    cmm.*
  FROM country_month_metrics AS cmm
  WHERE cmm.personal_avg_prev_2_months IS NOT NULL
    AND cmm.month_sum >= 3.0 * cmm.personal_avg_prev_2_months
    AND cmm.month_sum >= cmm.p95_month_sum
)
SELECT
  f.customer_id AS p02,
  c.h03 || ' ' || c.h04 AS customer_name,
  f.country_id AS country_id,
  f.month_start AS month,
  ROUND(f.month_sum, 2) AS month_payment_sum,
  f.month_payment_count AS month_payment_count,
  ROUND(f.personal_avg_prev_2_months, 2) AS personal_sliding_avg_prev_2_months,
  ROUND(f.month_sum - f.personal_avg_prev_2_months, 2) AS deviation_from_personal_avg,
  f.customer_country_month_rank AS country_rank_in_month,
  ROUND(f.off_store_payment_share, 4) AS off_store_payment_share,
  f.distinct_staff_count AS distinct_staff_count
FROM final_filtered AS f
JOIN cus AS c
  ON c.h01 = f.customer_id
ORDER BY
  f.month_start,
  f.country_id,
  f.customer_country_month_rank,
  f.customer_id;