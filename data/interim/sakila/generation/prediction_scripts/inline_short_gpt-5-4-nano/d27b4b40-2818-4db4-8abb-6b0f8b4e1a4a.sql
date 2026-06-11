SELECT AVG(CAST(prev.day_amount AS REAL))
      FROM daily_pay AS prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.pay_date >= date(dp.pay_date, '-30 days')
        AND prev.pay_date < dp.pay_date
    ) AS avg_prev_30d
  FROM daily_pay AS dp
),
qualified AS (
  SELECT
    dwp.*,
    dwp.day_amount / dwp.avg_prev_30d AS exceed_ratio,
    (SELECT COUNT(*)
     FROM daily_with_prev_avg x
     WHERE x.customer_id = dwp.customer_id
       AND x.avg_prev_30d IS NOT NULL
       AND x.day_amount >= dwp.day_amount
    ) AS day_rank_in_customer_sum
  FROM daily_with_prev_avg AS dwp
  WHERE dwp.avg_prev_30d IS NOT NULL
    AND dwp.avg_prev_30d > 0
    AND dwp.payment_count >= 1
    AND dwp.day_amount >= 3.0 * dwp.avg_prev_30d
    AND dwp.payment_count >= 3
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
)
SELECT
  cg.customer_id,
  cg.first_name,
  cg.last_name,
  cg.country,
  cg.city,
  q.pay_date AS payment_date,
  q.payment_count,
  ROUND(q.day_amount, 2) AS total_amount,
  ROUND(q.avg_prev_30d, 2) AS avg_daily_amount_prev_30d,
  ROUND(q.exceed_ratio, 2) AS exceed_ratio,
  q.day_rank_in_customer_sum AS day_rank_in_customer_sum
FROM qualified AS q
JOIN customer_geo AS cg
  ON cg.customer_id = q.customer_id
ORDER BY
  cg.country,
  cg.city,
  q.exceed_ratio DESC,
  q.pay_date,
  cg.customer_id;