SELECT DISTINCT
      bp.customer_id,
      bp.payment_month
    FROM base_pay bp
  ) AS b
  LEFT JOIN monthly_with_prev mwp
    ON mwp.customer_id = b.customer_id
   AND mwp.payment_month = b.payment_month
  WHERE mwp.payment_count IS NULL
     OR mwp.prev_avg_amount IS NULL
     OR mwp.payment_count < 5
     OR mwp.month_amount < 2.0 * mwp.prev_avg_amount
     OR NOT (mwp.distinct_staff_count >= 2 OR mwp.distinct_home_store_count >= 2)
  GROUP BY b.customer_id
),
qualified_customers AS (
  SELECT v.customer_id
  FROM violations v
  WHERE v.violation_months = 0
)
SELECT
  c.customer_id,
  m.payment_month AS month,
  m.country_name AS country,
  m.city_name AS city,
  ROUND(m.month_amount, 2) AS payment_sum,
  m.payment_count,
  ROUND((m.month_amount - m.prev_avg_amount), 2) AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY m.country_id, m.payment_month
    ORDER BY (m.month_amount - m.prev_avg_amount) DESC
  ) AS deviation_rank_in_country
FROM qualified_customers c
JOIN monthly_with_prev m
  ON m.customer_id = c.customer_id
WHERE m.prev_avg_amount IS NOT NULL
  AND m.payment_count >= 5
  AND m.month_amount >= 2.0 * m.prev_avg_amount
  AND (m.distinct_staff_count >= 2 OR m.distinct_home_store_count >= 2)
ORDER BY
  m.country_name,
  m.payment_month,
  deviation_rank_in_country,
  c.customer_id;