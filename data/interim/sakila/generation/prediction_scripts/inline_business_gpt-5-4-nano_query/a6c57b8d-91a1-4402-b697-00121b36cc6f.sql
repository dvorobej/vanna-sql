WITH RECURSIVE
months(month_start) AS (
  SELECT date('2005-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    cu.h03 || ' ' || cu.h04 AS customer_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ct.d02 AS city_name,
    p.p06 AS payment_date
  FROM pay p
  JOIN cus cu ON cu.h01 = p.p02
  JOIN adr a ON a.e01 = cu.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt ON cnt.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
),
monthly_customer AS (
  SELECT
    customer_id,
    customer_name,
    country_id,
    country_name,
    city_name,
    month_start,
    COUNT(payment_id) AS payment_count,
    SUM(payment_amount) AS payment_sum
  FROM payment_enriched
  GROUP BY
    customer_id, customer_name, country_id, country_name, city_name, month_start
),
monthly_with_personal AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (PARTITION BY mc.customer_id) AS personal_avg_monthly_amount
  FROM monthly_customer mc
),
country_month_ranked AS (
  SELECT
    mwp.*,
    RANK() OVER (
      PARTITION BY mwp.country_id, mwp.month_start
      ORDER BY mwp.payment_sum DESC
    ) AS country_month_sum_rank,
    COUNT(*) OVER (
      PARTITION BY mwp.country_id, mwp.month_start
    ) AS country_month_customer_count
  FROM monthly_with_personal mwp
),
filtered_suspicious AS (
  SELECT
    cmr.*,
    (cmr.payment_sum - cmr.personal_avg_monthly_amount) AS deviation_from_personal_avg,
    CAST(cmr.country_month_customer_count * 0.10 AS INTEGER) AS top10_floor
  FROM country_month_ranked cmr
  WHERE
    cmr.personal_avg_monthly_amount > 0
    AND cmr.payment_sum > 2.0 * cmr.personal_avg_monthly_amount
    AND cmr.country_month_sum_rank <= (
      CASE
        WHEN (cmr.country_month_customer_count * 0.10) > CAST(cmr.country_month_customer_count * 0.10 AS INTEGER)
          THEN CAST(cmr.country_month_customer_count * 0.10 AS INTEGER) + 1
        ELSE CAST(cmr.country_month_customer_count * 0.10 AS INTEGER)
      END
    )
),
top_staff_per_month AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    pe.staff_id,
    pe.payment_amount,
    ROW_NUMBER() OVER (
      PARTITION BY pe.customer_id, pe.month_start
      ORDER BY pe.payment_amount DESC, pe.payment_id DESC
    ) AS rn
  FROM payment_enriched pe
),
top_staff_chosen AS (
  SELECT
    ts.customer_id,
    ts.month_start,
    ts.staff_id
  FROM top_staff_per_month ts
  WHERE ts.rn = 1
)
SELECT
  fs.customer_id,
  fs.customer_name,
  fs.country_name AS country,
  fs.city_name AS city,
  strftime('%Y-%m', fs.month_start) AS payment_month,
  ROUND(fs.payment_sum, 2) AS payment_sum,
  fs.payment_count,
  ROUND(fs.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  fs.country_month_sum_rank AS country_month_customer_rank,
  st.o01 AS top_staff_id,
  st.o02 AS top_staff_first_name,
  st.o03 AS top_staff_last_name
FROM filtered_suspicious fs
JOIN top_staff_chosen tsc
  ON tsc.customer_id = fs.customer_id
 AND tsc.month_start = fs.month_start
JOIN stf st
  ON st.o01 = tsc.staff_id
ORDER BY
  fs.country_name,
  fs.month_start,
  fs.payment_sum DESC,
  fs.customer_id;