SELECT DISTINCT
      country_name,
      issuing_store_id,
      month_start,
      cnt_clients_in_group
    FROM country_store_month_rank
  )
),
p95_value AS (
  SELECT
    csr.country_name,
    csr.issuing_store_id,
    csr.month_start,
    csr.month_payment_sum AS p95_month_payment_sum
  FROM country_store_month_rank csr
  JOIN p95_threshold pt
    ON pt.country_name = csr.country_name
   AND pt.issuing_store_id = csr.issuing_store_id
   AND pt.month_start = csr.month_start
   AND csr.rn_asc = pt.p95_rn
),
-- 5) Отбираем месяцы, где сумма > 3*personal_avg_prev_months и > p95 по группе
suspects AS (
  SELECT
    csr.*,
    pv.p95_month_payment_sum
  FROM country_store_month_rank csr
  JOIN p95_value pv
    ON pv.country_name = csr.country_name
   AND pv.issuing_store_id = csr.issuing_store_id
   AND pv.month_start = csr.month_start
  WHERE csr.personal_avg_prev_months IS NOT NULL
    AND csr.personal_avg_prev_months > 0
    AND csr.month_payment_sum >= 3.0 * csr.personal_avg_prev_months
    AND csr.month_payment_sum > pv.p95_month_payment_sum
),
-- 6) Ранг клиента внутри магазина за этот месяц (по сумме)
ranked AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY issuing_store_id, month_start
      ORDER BY month_payment_sum DESC
    ) AS store_month_customer_rank
  FROM suspects s
)
SELECT
  customer_id,
  country_name,
  city_name,
  issuing_store_id AS store_id,
  strftime('%Y-%m', month_start) AS month,
  ROUND(month_payment_sum, 2) AS month_payment_sum,
  payment_count AS payment_count,
  distinct_staff_count AS distinct_staff_count,
  ROUND(share_late_returns, 4) AS share_late_returns,
  store_month_customer_rank
FROM ranked
ORDER BY
  month_start,
  country_name,
  issuing_store_id,
  month_payment_sum DESC,
  customer_id;