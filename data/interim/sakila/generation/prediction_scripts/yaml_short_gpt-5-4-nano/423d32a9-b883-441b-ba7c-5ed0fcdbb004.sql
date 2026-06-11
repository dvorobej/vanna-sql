SELECT '2005-01-01' AS month_start
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
),
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_total_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_staff_store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_enriched AS (
  SELECT
    cb.customer_id,
    cb.country_id,
    cb.country_name,
    cb.city_name,
    m.month_start,
    COALESCE(mp.month_total_amount, 0) AS month_total_amount,
    COALESCE(mp.payment_count, 0) AS payment_count,
    COALESCE(mp.distinct_staff_count, 0) AS distinct_staff_count,
    COALESCE(mp.distinct_staff_store_count, 0) AS distinct_staff_store_count
  FROM customer_base AS cb
  CROSS JOIN months AS m
  LEFT JOIN monthly_payments AS mp
    ON mp.customer_id = cb.customer_id
   AND mp.month_start = m.month_start
),
qualified_months AS (
  SELECT
    me.*,
    AVG(me.month_total_amount) OVER (
      PARTITION BY me.customer_id
      ORDER BY me.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_months_amount
  FROM monthly_enriched AS me
),
monthly_flags AS (
  SELECT
    qm.*,
    CASE
      WHEN qm.avg_prev_months_amount > 0
       AND qm.month_total_amount >= 2.0 * qm.avg_prev_months_amount
       AND qm.payment_count >= 5
       AND (qm.distinct_staff_count >= 2 OR qm.distinct_staff_store_count >= 2)
      THEN 1 ELSE 0
    END AS is_ok_month
  FROM qualified_months AS qm
  WHERE qm.month_start >= '2005-02-01' -- для января нет "предыдущих месяцев"
),
customers_all_months_ok AS (
  SELECT
    customer_id
  FROM monthly_flags
  GROUP BY customer_id
  HAVING SUM(is_ok_month) = 11
)
SELECT
  mf.month_start AS payment_month,
  mf.country_name,
  mf.city_name,
  mf.customer_id,
  ROUND(mf.month_total_amount, 2) AS month_total_amount,
  mf.payment_count,
  ROUND(mf.month_total_amount - mf.avg_prev_months_amount, 2) AS deviation_from_avg_prev,
  RANK() OVER (
    PARTITION BY mf.country_id, mf.month_start
    ORDER BY mf.month_total_amount DESC
  ) AS country_month_rank
FROM monthly_flags AS mf
JOIN customers_all_months_ok AS cmo
  ON cmo.customer_id = mf.customer_id
ORDER BY
  mf.month_start,
  mf.country_name,
  country_month_rank,
  mf.customer_id;