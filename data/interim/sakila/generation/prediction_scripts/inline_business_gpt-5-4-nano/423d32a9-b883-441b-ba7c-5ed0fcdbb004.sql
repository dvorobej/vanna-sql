WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS payment_month,
    s.o07 AS staff_store_id,
    cu.h03 AS first_name,
    cu.h04 AS last_name,
    co.c02 AS country,
    ci.d02 AS city
  FROM pay AS p
  JOIN cus AS cu
    ON cu.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = cu.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  JOIN stf AS s
    ON s.o01 = p.p03
),
customer_monthly AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    country,
    city,
    month_start,
    payment_month,
    COUNT(payment_id) AS payment_count,
    SUM(payment_amount) AS month_payment_sum,
    AVG(payment_amount) AS avg_payment_check,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT staff_store_id) AS distinct_staff_store_count
  FROM payment_base
  GROUP BY
    customer_id, first_name, last_name, country, city, month_start, payment_month
),
with_history AS (
  SELECT
    cm.*,
    AVG(cm.month_payment_sum) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_sum
  FROM customer_monthly AS cm
),
flagged_months AS (
  SELECT
    wh.*,
    (wh.month_payment_sum / NULLIF(wh.prev_avg_month_sum, 0.0)) AS ratio_to_prev_avg,
    (wh.month_payment_sum - wh.prev_avg_month_sum) AS deviation_from_prev_avg
  FROM with_history AS wh
  WHERE wh.prev_avg_month_sum IS NOT NULL
    AND wh.payment_count >= 5
    AND wh.month_payment_sum >= 2.0 * wh.prev_avg_month_sum
    AND (wh.distinct_staff_count >= 2 OR wh.distinct_staff_store_count >= 2)
),
rank_within_country_by_deviation AS (
  SELECT
    fm.*,
    RANK() OVER (
      PARTITION BY fm.country, fm.month_start
      ORDER BY fm.deviation_from_prev_avg DESC
    ) AS deviation_country_month_rank
  FROM flagged_months AS fm
),
final_per_month AS (
  SELECT
    r.country,
    r.city,
    r.month_start,
    r.payment_month,
    r.customer_id,
    r.first_name,
    r.last_name,
    ROUND(r.month_payment_sum, 2) AS month_payment_sum,
    r.payment_count,
    ROUND(r.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
    r.deviation_country_month_rank
  FROM rank_within_country_by_deviation AS r
)
SELECT *
FROM final_per_month
ORDER BY
  month_start,
  country,
  deviation_country_month_rank,
  customer_id;