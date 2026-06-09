SELECT AVG(dp2.day_sum)
      FROM daily_pay dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 days')
        AND dp2.payment_date < dp.payment_date
    ) AS avg_prev_30_day_sum
  FROM daily_pay dp
),
daily_suspicious AS (
  SELECT
    dwp.*,
    (dwp.day_sum / dwp.avg_prev_30_day_sum) AS ratio_vs_prev
  FROM daily_with_prev dwp
  WHERE dwp.avg_prev_30_day_sum IS NOT NULL
    AND dwp.avg_prev_30_day_sum > 0
    AND dwp.day_sum >= 3.0 * dwp.avg_prev_30_day_sum
    AND dwp.payment_count >= 3
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
),
daily_r_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(
      CASE
        WHEN ca.i11 IN ('R', 'NC-17') THEN CAST(p.p05 AS REAL)
        ELSE 0.0
      END
    ) AS r_nc17_sum,
    SUM(CAST(p.p05 AS REAL)) AS day_sum_total
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flm ca ON ca.i01 = i.n02
  GROUP BY
    p.p02,
    date(p.p06)
),
ranked_country_day AS (
  SELECT
    ds.*,
    ROW_NUMBER() OVER (
      PARTITION BY cg.country, ds.payment_date
      ORDER BY ds.day_sum DESC, ds.customer_id
    ) AS day_rank_in_country,
    drr.r_nc17_sum,
    drr.day_sum_total
  FROM daily_suspicious ds
  JOIN customer_geo cg ON cg.customer_id = ds.customer_id
  JOIN daily_r_share drr
    ON drr.customer_id = ds.customer_id
   AND drr.payment_date = ds.payment_date
)
SELECT
  cg.customer_id,
  cg.first_name,
  cg.last_name,
  cg.city,
  cg.country,
  ds.payment_date,
  ds.payment_count,
  ROUND(ds.day_sum, 2) AS day_sum,
  ROUND(ds.max_payment, 2) AS max_payment,
  ROUND(
    CASE
      WHEN ds.day_sum > 0 THEN (dr.r_nc17_sum * 1.0 / ds.day_sum_total)
      ELSE 0.0
    END,
    4
  ) AS r_nc17_rental_share,
  dr.day_rank_in_country AS country_day_rank
FROM ranked_country_day dr
JOIN customer_geo cg
  ON cg.customer_id = dr.customer_id
JOIN daily_with_prev ds
  ON ds.customer_id = dr.customer_id
 AND ds.payment_date = dr.payment_date
ORDER BY
  cg.country,
  country_day_rank,
  ds.payment_date,
  cg.last_name,
  cg.first_name;