WITH monthly_payments AS (
  SELECT
    c.h01 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    c.h03 || ' ' || c.h04 AS customer_name,
    p.p05 AS payment_amount,
    p.p01 AS payment_id,
    p.p03 AS staff_id,
    st.o07 AS staff_store_id,
    date(p.p06) AS payment_day
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  LEFT JOIN stf AS st
    ON st.o01 = p.p03
),
monthly_agg AS (
  SELECT
    customer_id,
    month_start,
    MAX(customer_name) AS customer_name,
    SUM(payment_amount) AS month_sum_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT payment_day) AS payment_days_count,
    MAX(payment_amount) AS max_payment_amount,
    SUM(CASE WHEN payment_amount = (SELECT MAX(p2.p05)
                                      FROM pay p2
                                      WHERE p2.p02 = mp.customer_id
                                        AND date(p2.p06, 'start of month') = mp.month_start)
             THEN payment_amount ELSE 0 END) AS max_payment_amount_sum_check,
    1.0 * MAX(payment_amount) / NULLIF(SUM(payment_amount), 0) AS max_payment_share,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT staff_store_id) AS distinct_store_count
  FROM monthly_payments AS mp
  GROUP BY
    customer_id,
    month_start
),
monthly_with_history AS (
  SELECT
    ma.*,
    AVG(month_sum_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_month_sum
  FROM monthly_agg AS ma
),
qualified_months AS (
  SELECT
    mwh.*
  FROM monthly_with_history AS mwh
  WHERE mwh.avg_prev_month_sum IS NOT NULL
    AND mwh.month_sum_amount >= 3.0 * mwh.avg_prev_month_sum
    AND mwh.payment_count >= 3
    AND (mwh.distinct_staff_count >= 3 OR mwh.distinct_store_count >= 3)
),
customer_location AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ci.d03
),
final_calc AS (
  SELECT
    qm.month_start AS month,
    cl.country_name,
    cl.city_name,
    qm.customer_id,
    qm.customer_name,
    qm.payment_count AS payments_count,
    qm.month_sum_amount AS total_amount,
    qm.max_payment_amount AS max_payment_amount,
    qm.max_payment_share AS max_payment_share,
    qm.distinct_staff_count AS distinct_staff_count,
    qm.distinct_store_count AS distinct_store_count,
    RANK() OVER (
      PARTITION BY cl.country_name, qm.month_start
      ORDER BY qm.month_sum_amount DESC
    ) AS customer_rank_in_country
  FROM qualified_months AS qm
  JOIN customer_location AS cl
    ON cl.customer_id = qm.customer_id
)
SELECT
  customer_id AS h01,
  customer_name AS customer_full_name,
  country_name AS c01_country,
  city_name AS d02_city,
  month,
  payments_count,
  ROUND(total_amount, 2) AS total_amount,
  ROUND(max_payment_amount, 2) AS max_payment_amount,
  ROUND(max_payment_share, 4) AS max_payment_share,
  distinct_staff_count,
  distinct_store_count,
  customer_rank_in_country
FROM final_calc
ORDER BY
  c01_country,
  month,
  total_amount DESC,
  h01;