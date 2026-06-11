SELECT COUNT(*)
    FROM monthly_customer AS mc2
    JOIN customer_geo AS cg2 ON cg2.customer_id = mc2.customer_id
    WHERE cg2.country_id = cg.country_id
      AND mc2.month_start = mc.month_start
      AND mc2.payment_sum > mc.payment_sum
  ) + 1 AS country_month_payment_rank
FROM personal_history AS ph
JOIN monthly_customer AS mc
  ON mc.customer_id = ph.customer_id
 AND mc.month_start = ph.month_start
JOIN customer_geo AS cg
  ON cg.customer_id = mc.customer_id
JOIN country_thresholds AS ct
  ON ct.country_id = cg.country_id
 AND ct.month_start = mc.month_start
WHERE ph.prev2_months_cnt = 2
  AND ph.prev2_avg_payment_sum > 0
  AND mc.payment_sum > 3.0 * ph.prev2_avg_payment_sum
  AND ct.p90_payment_sum IS NOT NULL
  AND mc.payment_sum >= ct.p90_payment_sum
ORDER BY
  mc.month_start,
  cg.country_name,
  country_month_payment_rank,
  mc.customer_id;