SELECT date('2005-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    c.h03,
    c.h04,
    a.e01 AS address_id,
    ct.d02 AS city,
    co.c01 AS country_id,
    co.c02 AS country,
    co.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
base_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p01 AS payment_id,
    p.p05 AS amount,
    p.p03 AS staff_id,
    r.q01 AS rental_id,
    r.q04 AS customer_id_by_rental
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
   AND r.q04 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
monthly_customer AS (
  SELECT
    bp.customer_id,
    bp.month_start,
    COUNT(*) AS payment_count,
    SUM(bp.amount) AS payment_sum
  FROM base_pay AS bp
  GROUP BY
    bp.customer_id,
    bp.month_start
),
monthly_with_prev AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_months_avg_payment_sum,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_months_count
  FROM monthly_customer AS mc
),
suspicious_months AS (
  SELECT
    mwp.customer_id,
    mwp.month_start,
    mwp.payment_count,
    mwp.payment_sum,
    mwp.prev_2_months_avg_payment_sum,
    (mwp.payment_sum - mwp.prev_2_months_avg_payment_sum) AS deviation_from_2mo_avg,
    (mwp.payment_sum / NULLIF(mwp.prev_2_months_avg_payment_sum, 0.0)) AS ratio_vs_2mo_avg
  FROM monthly_with_prev AS mwp
  WHERE mwp.payment_count >= 3
    AND mwp.prev_2_months_count = 2
    AND mwp.prev_2_months_avg_payment_sum > 0
    AND mwp.payment_sum >= 2.0 * mwp.prev_2_months_avg_payment_sum
),
top_staff_per_month AS (
  SELECT
    bp.customer_id,
    bp.month_start,
    bp.staff_id,
    SUM(bp.amount) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY bp.customer_id, bp.month_start
      ORDER BY SUM(bp.amount) DESC, bp.staff_id
    ) AS rn
  FROM base_pay AS bp
  GROUP BY
    bp.customer_id,
    bp.month_start,
    bp.staff_id
),
ranked_suspicious AS (
  SELECT
    sm.*,
    RANK() OVER (
      PARTITION BY cg.store_id, sm.month_start
      ORDER BY sm.payment_sum DESC
    ) AS store_month_rank
  FROM suspicious_months AS sm
  JOIN customer_geo AS cg
    ON cg.customer_id = sm.customer_id
),
store_suspicious_totals AS (
  SELECT
    cg.store_id,
    cg.customer_id,
    SUM(rs.payment_sum) AS suspicious_payment_sum_total
  FROM ranked_suspicious AS rs
  JOIN customer_geo AS cg
    ON cg.customer_id = rs.customer_id
  GROUP BY
    cg.store_id,
    cg.customer_id
),
store_top10_cut AS (
  SELECT
    st.store_id,
    st.customer_id,
    st.suspicious_payment_sum_total,
    PERCENT_RANK() OVER (
      PARTITION BY st.store_id
      ORDER BY st.suspicious_payment_sum_total DESC
    ) AS pr
  FROM store_suspicious_totals AS st
)
SELECT
  rs.customer_id AS h01,
  cg.h03 AS customer_first_name,
  cg.h04 AS customer_last_name,
  rs.month_start,
  strftime('%Y-%m', rs.month_start) AS payment_month,
  cg.store_id AS h02_store_id,
  rs.payment_count,
  ROUND(rs.payment_sum, 2) AS monthly_suspicious_payment_sum,
  ROUND(rs.prev_2_months_avg_payment_sum, 2) AS prev_2_months_avg_payment_sum,
  ROUND(rs.deviation_from_2mo_avg, 2) AS deviation_from_2mo_avg,
  rs.store_month_rank AS rank_within_store_h02,
  sto.j01 AS sto_store_j01,
  adr.e01 AS address_id,
  cg.city,
  cg.country_id,
  cg.country_name,
  stf.o01 AS top_staff_id,
  stf.o02 AS top_staff_first_name,
  stf.o03 AS top_staff_last_name,
  ROUND(tsp.staff_payment_sum, 2) AS top_staff_payment_sum_in_month
FROM ranked_suspicious AS rs
JOIN customer_geo AS cg
  ON cg.customer_id = rs.customer_id
JOIN sto
  ON sto.j01 = cg.store_id
JOIN adr
  ON adr.e01 = cg.address_id
JOIN cnt
  ON cnt.c01 = cg.country_id
LEFT JOIN top_staff_per_month AS tsp
  ON tsp.customer_id = rs.customer_id
 AND tsp.month_start = rs.month_start
 AND tsp.rn = 1
LEFT JOIN stf
  ON stf.o01 = tsp.staff_id
JOIN store_top10_cut AS cut
  ON cut.store_id = cg.store_id
 AND cut.customer_id = rs.customer_id
WHERE cut.pr <= 0.1
ORDER BY
  cg.store_id,
  rs.month_start,
  rs.payment_sum DESC,
  rs.customer_id;