WITH monthly_pay AS (
  SELECT
    c.h01 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p01 AS payment_id,
    p.p03 AS staff_id,
    st.o07 AS staff_store_id,
    ci.j01 AS customer_store_id,
    a.e01 AS customer_address_id,
    c.h06 AS customer_address_fk
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS st
    ON st.o01 = p.p03
  JOIN sto AS ci
    ON ci.j01 = c.h02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
monthly_agg AS (
  SELECT
    customer_id,
    payment_month,
    customer_store_id,
    SUM(payment_amount) AS month_total_amount,
    COUNT(*) AS payment_count,
    SUM(CASE WHEN staff_store_id <> customer_store_id THEN 1 ELSE 0 END) AS payments_through_other_store_count,
    COUNT(DISTINCT staff_id) AS distinct_staff_count
  FROM monthly_pay
  GROUP BY customer_id, payment_month, customer_store_id
),
history AS (
  SELECT
    ma.*,
    AVG(month_total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY payment_month
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_avg_amount,
    COUNT(*) OVER (
      PARTITION BY customer_id
      ORDER BY payment_month
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_months_count
  FROM monthly_agg AS ma
),
qualified_months AS (
  SELECT
    h.*
  FROM history AS h
  WHERE prev2_months_count = 2
    AND payment_count >= 3
    AND month_total_amount >= 2.0 * prev2_avg_amount
),
store_top10_threshold AS (
  SELECT
    customer_store_id,
    payment_month,
    month_total_amount,
    PERCENT_RANK() OVER (
      PARTITION BY customer_store_id, payment_month
      ORDER BY month_total_amount DESC
    ) AS pr
  FROM qualified_months
),
qualified_months_top10 AS (
  SELECT
    qm.*
  FROM qualified_months AS qm
  JOIN (
    SELECT
      customer_store_id,
      payment_month,
      month_total_amount
    FROM store_top10_threshold
    WHERE pr <= 0.10
  ) AS t
    ON t.customer_store_id = qm.customer_store_id
   AND t.payment_month = qm.payment_month
   AND t.month_total_amount = qm.month_total_amount
),
final_enriched AS (
  SELECT
    qm.customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    qm.customer_store_id AS store_id,
    a.e05 AS customer_city_id,
    ct.d02 AS customer_city,
    cn.c02 AS customer_country,
    qm.payment_month,
    qm.month_total_amount AS month_total_amount,
    qm.payment_count,
    qm.prev2_avg_amount AS sliding_prev2_avg_amount,
    ROUND(qm.month_total_amount - qm.prev2_avg_amount, 2) AS deviation_from_prev2_avg,
    RANK() OVER (
      PARTITION BY qm.customer_store_id, qm.payment_month
      ORDER BY qm.month_total_amount DESC
    ) AS rank_within_store_month,
    (
      SELECT
        p2.p03
      FROM pay AS p2
      JOIN ren r2 ON r2.q01 = p2.p04
      JOIN inv i2 ON i2.n01 = r2.q03
      WHERE p2.p02 = qm.customer_id
        AND strftime('%Y-%m', p2.p06) = qm.payment_month
      GROUP BY p2.p03
      ORDER BY SUM(p2.p05) DESC
      LIMIT 1
    ) AS top_staff_id
  FROM qualified_months_top10 AS qm
  JOIN cus AS c
    ON c.h01 = qm.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
)
SELECT
  customer_id,
  customer_first_name,
  customer_last_name,
  store_id,
  customer_city,
  customer_country,
  payment_month,
  ROUND(month_total_amount, 2) AS month_total_amount,
  payment_count,
  ROUND(sliding_prev2_avg_amount, 2) AS rolling_prev2_avg_amount,
  ROUND(deviation_from_prev2_avg, 2) AS deviation_from_prev2_avg,
  rank_within_store_month,
  top_staff_id
FROM final_enriched
ORDER BY
  store_id,
  payment_month,
  rank_within_store_month,
  customer_id;