SELECT *
  FROM scored
  WHERE personal_avg_prev2 > 0
    AND month_sum >= 2.0 * personal_avg_prev2
    AND month_sum >= COALESCE(p95_month_amount_sum, 0)
    AND staff_not_home_share >= 0.10
),
ranked AS (
  SELECT
    s.*,
    RANK() OVER (
      PARTITION BY s.country_id, s.month_start
      ORDER BY s.month_sum DESC
    ) AS country_month_amount_rank
  FROM suspicious AS s
)
SELECT
  r.month_start AS payment_month,
  r.country,
  r.city,
  r.customer_id,
  cg.first_name,
  cg.last_name,
  ROUND(r.month_sum, 2) AS month_payment_sum,
  r.payment_count,
  ROUND(r.deviation_from_personal_avg_prev2, 2) AS deviation_from_personal_avg_prev2,
  ROUND(r.staff_not_home_share, 4) AS staff_not_home_payment_share,
  r.staff_count,
  r.country_month_amount_rank,
  ROUND(r.p95_month_amount_sum, 2) AS country_p95_month_amount_sum
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
  r.country,
  r.payment_month,
  r.country_month_amount_rank,
  r.customer_id;