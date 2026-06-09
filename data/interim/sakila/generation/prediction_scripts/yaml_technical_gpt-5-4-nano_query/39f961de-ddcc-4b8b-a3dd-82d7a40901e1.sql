SELECT AVG(d2.daily_sum)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_daily_prev_30
  FROM daily AS d
),
qualified_days AS (
  SELECT
    w.*,
    (
      SELECT
        1.0 * SUM(CASE WHEN pe.rating IN ('R','NC-17') THEN pe.payment_amount ELSE 0 END)
        / NULLIF(SUM(pe.payment_amount),0)
      FROM pay_enriched AS pe
      WHERE pe.customer_id = w.customer_id
        AND pe.payment_date = w.payment_date
    ) AS r_nc17_rental_share
  FROM with_prev_avg AS w
  WHERE w.avg_daily_prev_30 IS NOT NULL
    AND w.avg_daily_prev_30 > 0
    AND w.payment_count >= 3
    AND w.daily_sum >= 3 * w.avg_daily_prev_30
    AND (w.staff_count >= 2 OR w.store_count >= 2)
),
ranked AS (
  SELECT
    q.*,
    DENSE_RANK() OVER (
      PARTITION BY q.country_id, q.payment_date
      ORDER BY q.daily_sum DESC
    ) AS day_rank_in_country
  FROM qualified_days AS q
)
SELECT
  r.customer_id,
  r.city,
  r.country,
  r.payment_date AS day_date,
  r.payment_count,
  ROUND(r.daily_sum, 2) AS day_sum,
  ROUND(r.max_payment, 2) AS max_payment,
  ROUND(r.r_nc17_rental_share, 4) AS r_nc17_rental_share,
  r.day_rank_in_country
FROM ranked AS r
ORDER BY
  r.country,
  r.day_rank_in_country,
  r.payment_date,
  r.customer_id;