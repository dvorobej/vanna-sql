WITH RECURSIVE
payment_bounds AS (
  SELECT
    date(MIN(p06), 'start of month') AS min_month,
    date(MAX(p06), 'start of month') AS max_month
  FROM pay
),
months(month_start) AS (
  SELECT min_month
  FROM payment_bounds
  WHERE min_month IS NOT NULL

  UNION ALL

  SELECT date(month_start, '+1 month')
  FROM months
  CROSS JOIN payment_bounds
  WHERE month_start < max_month
),
customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 AS first_name,
    cus.h04 AS last_name,
    cnt.c01 AS customer_country_id,
    cnt.c02 AS customer_country
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
payment_enriched AS (
  SELECT
    pay.p01 AS payment_id,
    pay.p02 AS customer_id,
    date(pay.p06, 'start of month') AS payment_month,
    CAST(pay.p05 AS REAL) AS payment_amount,
    pay.p03 AS staff_id,
    stf.o07 AS store_id,
    store_cnt.c01 AS store_country_id
  FROM pay
  JOIN stf
    ON stf.o01 = pay.p03
  JOIN sto
    ON sto.j01 = stf.o07
  JOIN adr AS store_adr
    ON store_adr.e01 = sto.j03
  JOIN cty AS store_cty
    ON store_cty.d01 = store_adr.e05
  JOIN cnt AS store_cnt
    ON store_cnt.c01 = store_cty.d03
),
customer_month_grid AS (
  SELECT
    cg.customer_id,
    cg.first_name,
    cg.last_name,
    cg.customer_country_id,
    cg.customer_country,
    m.month_start
  FROM customer_geo AS cg
  CROSS JOIN months AS m
),
monthly_payments AS (
  SELECT
    pe.customer_id,
    pe.payment_month,
    COUNT(*) AS payment_count,
    SUM(pe.payment_amount) AS monthly_amount,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pe.store_id) AS distinct_store_count,
    MAX(
      CASE
        WHEN pe.store_country_id <> cg.customer_country_id THEN 1
        ELSE 0
      END
    ) AS has_foreign_store_payment
  FROM payment_enriched AS pe
  JOIN customer_geo AS cg
    ON cg.customer_id = pe.customer_id
  GROUP BY
    pe.customer_id,
    pe.payment_month
),
monthly_history AS (
  SELECT
    cmg.customer_id,
    cmg.first_name,
    cmg.last_name,
    cmg.customer_country,
    cmg.month_start,
    COALESCE(mp.payment_count, 0) AS payment_count,
    COALESCE(mp.monthly_amount, 0.0) AS monthly_amount,
    COALESCE(mp.distinct_staff_count, 0) AS distinct_staff_count,
    COALESCE(mp.distinct_store_count, 0) AS distinct_store_count,
    COALESCE(mp.has_foreign_store_payment, 0) AS has_foreign_store_payment,
    AVG(COALESCE(mp.monthly_amount, 0.0)) OVER (
      PARTITION BY cmg.customer_id
      ORDER BY cmg.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS historical_avg_monthly_amount
  FROM customer_month_grid AS cmg
  LEFT JOIN monthly_payments AS mp
    ON mp.customer_id = cmg.customer_id
   AND mp.payment_month = cmg.month_start
),
suspicious_months AS (
  SELECT
    *,
    monthly_amount - historical_avg_monthly_amount AS deviation_from_historical_avg,
    monthly_amount / NULLIF(historical_avg_monthly_amount, 0) AS exceedance_ratio
  FROM monthly_history
  WHERE payment_count >= 5
    AND historical_avg_monthly_amount > 0
    AND monthly_amount > historical_avg_monthly_amount * 2
    AND has_foreign_store_payment = 1
)
SELECT
  strftime('%Y-%m', month_start) AS payment_month,
  customer_id,
  first_name || ' ' || last_name AS customer_full_name,
  customer_country,
  payment_count,
  ROUND(monthly_amount, 2) AS monthly_payment_amount,
  ROUND(historical_avg_monthly_amount, 2) AS historical_avg_monthly_amount,
  ROUND(deviation_from_historical_avg, 2) AS deviation_from_historical_avg,
  ROUND(exceedance_ratio, 2) AS exceedance_ratio,
  distinct_staff_count,
  distinct_store_count,
  RANK() OVER (
    PARTITION BY month_start
    ORDER BY exceedance_ratio DESC, deviation_from_historical_avg DESC
  ) AS month_risk_rank
FROM suspicious_months
ORDER BY
  month_start,
  month_risk_rank,
  monthly_payment_amount DESC,
  customer_id;