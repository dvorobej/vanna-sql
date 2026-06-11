WITH
monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_amount
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_with_prev AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount
  FROM monthly_customer AS mc
),
eligible_months AS (
  SELECT
    cwp.customer_id,
    cwp.month_start,
    cwp.month_amount,
    cwp.payment_count,
    cwp.prev_avg_month_amount
  FROM customer_with_prev AS cwp
  WHERE cwp.prev_avg_month_amount IS NOT NULL
    AND cwp.payment_count >= 5
    AND cwp.month_amount > 3.0 * cwp.prev_avg_month_amount
),
pay_detail AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p01 AS payment_id,
    p.p03 AS staff_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    s.o02 AS staff_store_id,
    ci.d02 AS customer_city,
    co.c02 AS customer_country,
    si.d02 AS staff_city,
    sc.c02 AS staff_country,
    CASE
      WHEN si.d02 <> ci.d02 OR sc.c02 <> co.c02 THEN 1
      ELSE 0
    END AS is_other_store_geo,
    ca.l02 AS category_id
  FROM pay AS p
  JOIN eligible_months em
    ON em.customer_id = p.p02
   AND em.month_start = date(p.p06, 'start of month')
  JOIN ren r
    ON r.q01 = p.p04
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flm f
    ON f.i01 = i.n02
  JOIN flc fc
    ON fc.l01 = f.i01
  JOIN cat ca
    ON ca.g01 = fc.l02
  JOIN cus cus
    ON cus.h01 = p.p02
  JOIN adr a_c
    ON a_c.e01 = cus.h06
  JOIN cty ci
    ON ci.d01 = a_c.e05
  JOIN sto s
    ON s.j01 = cus.h02
  JOIN sto s_store
    ON s_store.j01 = i.n03
  JOIN adr a_s
    ON a_s.e01 = s_store.j03
  JOIN cty si
    ON si.d01 = a_s.e05
  JOIN cnt co
    ON co.c01 = ci.d03
  JOIN cnt sc
    ON sc.c01 = si.d03
  LEFT JOIN stf st
    ON st.o01 = p.p03
  JOIN sto s
    ON s.j01 = st.o02
),
monthly_other_store AS (
  SELECT
    pd.customer_id,
    pd.month_start,
    SUM(pd.is_other_store_geo) AS other_geo_payment_count,
    COUNT(*) AS payment_count_detail,
    SUM(pd.payment_amount) AS month_amount_detail,
    MAX(pd.payment_amount) AS max_payment
  FROM pay_detail pd
  GROUP BY
    pd.customer_id,
    pd.month_start
),
category_rollup AS (
  SELECT
    pd.customer_id,
    pd.month_start,
    GROUP_CONCAT(pd.category_id) AS category_ids
  FROM pay_detail pd
  GROUP BY
    pd.customer_id,
    pd.month_start
),
customer_rank_in_month AS (
  SELECT
    em.customer_id,
    em.month_start,
    RANK() OVER (
      PARTITION BY em.month_start
      ORDER BY em.month_amount DESC
    ) AS customer_month_rank
  FROM eligible_months em
),
monthly_filtered AS (
  SELECT
    em.customer_id,
    em.month_start,
    mos.month_amount_detail AS month_amount,
    mos.payment_count_detail AS payment_count,
    mos.other_geo_payment_count AS other_store_payment_count,
    mos.max_payment,
    (1.0 * mos.other_geo_payment_count / NULLIF(mos.payment_count_detail, 0)) AS other_store_payment_share
  FROM eligible_months em
  JOIN monthly_other_store mos
    ON mos.customer_id = em.customer_id
   AND mos.month_start = em.month_start
)
SELECT
  mf.month_start AS month,
  mf.customer_id,
  mf.month_amount AS total_payment_amount,
  mf.payment_count AS payment_count,
  ROUND(mf.other_store_payment_share, 4) AS other_store_payment_share,
  ROUND(mf.max_payment, 2) AS max_payment,
  cr.customer_month_rank,
  cr2.category_ids AS category_list
FROM monthly_filtered mf
JOIN customer_rank_in_month cr
  ON cr.customer_id = mf.customer_id
 AND cr.month_start = mf.month_start
JOIN category_rollup cr2
  ON cr2.customer_id = mf.customer_id
 AND cr2.month_start = mf.month_start
WHERE
  mf.other_store_payment_share > 0
ORDER BY
  mf.month_start,
  mf.month_amount DESC,
  mf.customer_id;