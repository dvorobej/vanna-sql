WITH monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS month_payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
monthly_with_prev AS (
  SELECT
    mp.*,
    date(mp.payment_month || '-01') AS month_start,
    AVG(mp.month_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY date(mp.payment_month || '-01')
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev3_avg_amount,
    AVG(mp.month_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY date(mp.payment_month || '-01')
      ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
    ) AS prev6_avg_amount
  FROM monthly_payments AS mp
),
country_month AS (
  SELECT
    payment_month,
    customer_id,
    month_amount
  FROM monthly_with_prev
),
country_month_ranks AS (
  SELECT
    cm.*,
    DENSE_RANK() OVER (
      PARTITION BY cm.payment_month
      ORDER BY cm.month_amount DESC
    ) AS amount_desc_dense_rank,
    COUNT(*) OVER (
      PARTITION BY cm.payment_month
    ) AS country_customers_count
  FROM country_month AS cm
),
country_month_top5 AS (
  SELECT
    payment_month,
    customer_id,
    month_amount,
    CASE
      WHEN (amount_desc_dense_rank * 1.0) / NULLIF(country_customers_count, 0) <= 0.05 THEN 1
      ELSE 0
    END AS is_top5pct_country
  FROM country_month_ranks
),
country_month_median AS (
  -- median of monthly_amount per country is not possible with a single table key because
  -- schema lacks "country" in pay/cus;