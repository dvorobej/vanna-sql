SELECT AVG(d2.day_amount)
      FROM daily_customer AS d2
      WHERE d2.customer_id = dc.customer_id
        AND d2.payment_date >= date(dc.payment_date, '-30 day')
        AND d2.payment_date < dc.payment_date
    ), 0.0) AS avg_day_amount_prev_30d
  FROM daily_customer AS dc
  WHERE dc.payment_date >= '2005-01-01'
    AND dc.payment_date < '2006-01-01'
),
daily_suspicious AS (
  SELECT
    d.*,
    CASE
      WHEN d.avg_day_amount_prev_30d > 0 THEN d.day_amount / (2.0 * d.avg_day_amount_prev_30d)
      ELSE NULL
    END AS exceed_over_prev_avg_times_2,
    CASE
      WHEN d.avg_day_amount_prev_30d > 0 THEN d.day_amount / d.avg_day_amount_prev_30d
      ELSE NULL
    END AS exceed_ratio_vs_prev_avg
  FROM daily_with_prev_avg AS d
  WHERE d.payment_count >= 3
    AND d.distinct_staff_count >= 2
    AND d.distinct_store_count >= 2
    AND d.cross_country_payment_count >= 1
    AND d.avg_day_amount_prev_30d > 0
    AND d.day_amount >= 2.0 * d.avg_day_amount_prev_30d
),
country_rank AS (
  SELECT
    customer_id,
    customer_country,
    payment_date,
    day_amount,
    exceed_ratio_vs_prev_avg,
    DENSE_RANK() OVER (
      PARTITION BY customer_country
      ORDER BY exceed_ratio_vs_prev_avg DESC, day_amount DESC, customer_id
    ) AS country_exceed_rank
  FROM daily_suspicious
)
SELECT
  cr.customer_id,
  cg.customer_country,
  cr.payment_date,
  ROUND(ds.day_amount, 2) AS day_amount,
  ROUND(ds.avg_day_amount_prev_30d, 2) AS avg_day_amount_prev_30d,
  ROUND(ds.exceed_ratio_vs_prev_avg, 3) AS exceed_ratio_vs_prev_avg,
  cr.country_exceed_rank
FROM country_rank AS cr
JOIN daily_suspicious AS ds
  ON ds.customer_id = cr.customer_id
 AND ds.payment_date = cr.payment_date
JOIN customer_geo AS cg
  ON cg.customer_id = cr.customer_id
ORDER BY
  cg.customer_country,
  cr.country_exceed_rank,
  cr.payment_date,
  cr.customer_id;