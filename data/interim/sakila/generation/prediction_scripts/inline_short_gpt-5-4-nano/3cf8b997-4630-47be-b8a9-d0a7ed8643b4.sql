WITH monthly_pay AS (
  SELECT
    s.o07 AS store_id,
    date(p.p06, 'start of month') AS month_start,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_payment_sum
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN ren AS r
    ON r.q01 = p.p04
  WHERE date(p.p06) >= '2005-01-01'
    AND date(p.p06) < '2006-01-01'
  GROUP BY
    s.o07,
    date(p.p06, 'start of month'),
    p.p02,
    p.p03
),
monthly_store_customer AS (
  SELECT
    store_id,
    month_start,
    customer_id,
    SUM(month_payment_sum) AS month_payment_sum,
    SUM(payment_count) AS payment_count
  FROM monthly_pay
  GROUP BY
    store_id,
    month_start,
    customer_id
),
store_month_customer_with_prev AS (
  SELECT
    ms.customer_id,
    ms.store_id,
    ms.month_start,
    ms.payment_count,
    ms.month_payment_sum,
    AVG(ms2.month_payment_sum) AS avg_prev_2_months
  FROM monthly_store_customer AS ms
  LEFT JOIN monthly_store_customer AS ms2
    ON ms2.store_id = ms.store_id
   AND ms2.customer_id = ms.customer_id
   AND ms2.month_start IN (
        date(ms.month_start, '-1 month'),
        date(ms.month_start, '-2 months')
   )
  GROUP BY
    ms.customer_id,
    ms.store_id,
    ms.month_start,
    ms.payment_count,
    ms.month_payment_sum
),
qualified_per_month AS (
  SELECT
    store_id,
    month_start,
    customer_id,
    payment_count,
    month_payment_sum,
    avg_prev_2_months,
    (month_payment_sum - avg_prev_2_months) AS deviation_sum,
    CASE
      WHEN avg_prev_2_months IS NULL OR avg_prev_2_months = 0 THEN NULL
      ELSE month_payment_sum / avg_prev_2_months
    END AS ratio_to_prev_avg
  FROM store_month_customer_with_prev
  WHERE avg_prev_2_months IS NOT NULL
    AND payment_count >= 3
    AND month_payment_sum >= 2.0 * avg_prev_2_months
),
store_top10_suspicious AS (
  SELECT
    q.store_id,
    q.month_start,
    q.customer_id,
    q.payment_count,
    q.month_payment_sum,
    q.deviation_sum,
    q.ratio_to_prev_avg,
    RANK() OVER (
      PARTITION BY q.store_id, q.month_start
      ORDER BY q.month_payment_sum DESC
    ) AS suspicious_rank_in_store_month
  FROM qualified_per_month AS q
),
store_month_threshold AS (
  SELECT
    store_id,
    month_start,
    PERCENT_RANK() OVER (PARTITION BY store_id, month_start ORDER BY month_payment_sum DESC) AS pr
  FROM store_top10_suspicious
),
final_qualified AS (
  SELECT
    st10.*
  FROM store_top10_suspicious AS st10
  JOIN (
    SELECT DISTINCT store_id, month_start,
      PERCENT_RANK() OVER (PARTITION BY store_id, month_start ORDER BY month_payment_sum DESC) AS pr
    FROM store_top10_suspicious
  ) AS t
    ON t.store_id = st10.store_id
   AND t.month_start = st10.month_start
   AND t.pr = 0.0
)
SELECT
  st.store_id AS store_id,
  st.j02 AS store_name,
  ci.d02 AS city,
  co.c02 AS country,
  strftime('%Y-%m', fq.month_start) AS month,
  ROUND(fq.month_payment_sum, 2) AS month_sum,
  fq.payment_count,
  ROUND(fq.deviation_sum, 2) AS deviation_sum,
  fq.suspicious_rank_in_store_month AS rank_in_store_month,
  stf_best.o01 AS staff_id,
  stf_best.o02 AS staff_first_name,
  stf_best.o03 AS staff_last_name,
  ROUND(stf_best_staff_sum.month_staff_sum, 2) AS staff_max_month_payment_sum
FROM final_qualified AS fq
JOIN sto AS st
  ON st.j01 = fq.store_id
JOIN adr AS a_store
  ON a_store.e01 = st.j03
JOIN cty AS ci
  ON ci.d01 = a_store.e05
JOIN cnt AS co
  ON co.c01 = ci.d03
LEFT JOIN (
  SELECT
    p.store_id,
    p.month_start,
    p.customer_id,
    p.staff_id,
    p.month_staff_sum
  FROM (
    SELECT
      s.o07 AS store_id,
      date(p.p06, 'start of month') AS month_start,
      p.p02 AS customer_id,
      p.p03 AS staff_id,
      SUM(p.p05) AS month_staff_sum,
      RANK() OVER (
        PARTITION BY s.o07, date(p.p06, 'start of month'), p.p02
        ORDER BY SUM(p.p05) DESC
      ) AS staff_rank
    FROM pay AS p
    JOIN stf AS s
      ON s.o01 = p.p03
    WHERE date(p.p06) >= '2005-01-01'
      AND date(p.p06) < '2006-01-01'
    GROUP BY
      s.o07,
      date(p.p06, 'start of month'),
      p.p02,
      p.p03
  ) p
  WHERE p.staff_rank = 1
) AS stf_best_staff_sum
  ON stf_best_staff_sum.store_id = fq.store_id
 AND stf_best_staff_sum.month_start = fq.month_start
 AND stf_best_staff_sum.customer_id = fq.customer_id
LEFT JOIN stf AS stf_best
  ON stf_best.o01 = stf_best_staff_sum.staff_id
ORDER BY
  fq.store_id,
  fq.month_start,
  fq.suspicious_rank_in_store_month;