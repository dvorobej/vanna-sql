WITH
base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS customer_store_id,
    s.o03 AS staff_store_manager_id,
    ci.d02 AS city_name,
    co.c02 AS country_name,
    i.n03 AS issuing_store_id,
    CASE
      WHEN i.n03 = c.h02 THEN 1 ELSE 0
    END AS is_same_store_rental
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN stf s
    ON s.o01 = p.p03
  JOIN adr ca
    ON ca.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = ca.e05
  JOIN cnt co
    ON co.c01 = ci.d03
  LEFT JOIN ren r
    ON r.q01 = p.p04
  LEFT JOIN inv i
    ON i.n01 = r.q03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
monthly AS (
  SELECT
    customer_id,
    customer_store_id,
    city_name,
    country_name,
    month_start,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_payment_sum
  FROM base
  GROUP BY
    customer_id,
    customer_store_id,
    city_name,
    country_name,
    month_start
),
with_history AS (
  SELECT
    m.*,
    AVG(month_payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_month_avg_sum,
    COUNT(*) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_months_count
  FROM monthly m
),
suspicious_months AS (
  SELECT
    wh.*,
    CASE
      WHEN prev2_months_count = 2
       AND prev2_month_avg_sum > 0
       AND month_payment_sum >= 2.0 * prev2_month_avg_sum
      THEN 1 ELSE 0
    END AS meets_multiplier_rule
  FROM with_history wh
),
store_month_ranked AS (
  SELECT
    sm.*,
    RANK() OVER (
      PARTITION BY customer_store_id, month_start
      ORDER BY month_payment_sum DESC
    ) AS store_month_amount_rank,
    COUNT(*) OVER (
      PARTITION BY customer_store_id, month_start
    ) AS store_month_customers_cnt
  FROM suspicious_months sm
  WHERE meets_multiplier_rule = 1
),
qualified_months AS (
  SELECT
    smr.*
  FROM store_month_ranked smr
  WHERE
    -- top-10% among clients of the same store (for that month)
    smr.store_month_amount_rank <= CAST(0.1 * smr.store_month_customers_cnt AS INTEGER) + 1
),
top_store_month_customer AS (
  SELECT
    qm.customer_id,
    qm.customer_store_id,
    qm.city_name,
    qm.country_name,
    qm.month_start,
    qm.payment_count,
    qm.month_payment_sum,
    qm.prev2_month_avg_sum,
    (qm.month_payment_sum - qm.prev2_month_avg_sum) AS deviation_from_moving_avg,
    RANK() OVER (
      PARTITION BY qm.customer_store_id, qm.month_start
      ORDER BY qm.month_payment_sum DESC
    ) AS month_rank_in_store
  FROM qualified_months qm
),
staff_top_payment AS (
  SELECT
    b.customer_id,
    b.customer_store_id,
    date(b.payment_date, 'start of month') AS month_start,
    b.staff_id,
    SUM(b.payment_amount) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY b.customer_id, date(b.payment_date, 'start of month')
      ORDER BY SUM(b.payment_amount) DESC
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      c.h02 AS customer_store_id,
      p.p03 AS staff_id,
      p.p06 AS payment_date,
      p.p05 AS payment_amount
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
  ) b
  GROUP BY
    b.customer_id,
    b.customer_store_id,
    date(b.payment_date, 'start of month'),
    b.staff_id
),
final_staff_top AS (
  SELECT
    stp.customer_id,
    stp.customer_store_id,
    stp.month_start,
    stp.staff_id
  FROM staff_top_payment stp
  WHERE stp.rn = 1
)
SELECT
  tsmc.customer_store_id AS store_id,
  tsmc.city_name AS city,
  tsmc.country_name AS country,
  strftime('%Y-%m', tsmc.month_start) AS month,
  tsmc.month_payment_sum AS payment_sum,
  tsmc.payment_count AS payment_count,
  ROUND(tsmc.deviation_from_moving_avg, 2) AS deviation_from_moving_avg,
  tsmc.month_rank_in_store AS rank_in_store,
  st.o02 AS staff_first_name,
  st.o03 AS staff_last_name,
  st.o06 AS staff_email
FROM top_store_month_customer tsmc
JOIN final_staff_top fst
  ON fst.customer_id = tsmc.customer_id
 AND fst.customer_store_id = tsmc.customer_store_id
 AND fst.month_start = tsmc.month_start
JOIN stf st
  ON st.o01 = fst.staff_id
ORDER BY
  tsmc.month_start,
  tsmc.customer_store_id,
  tsmc.month_rank_in_store,
  tsmc.customer_id;