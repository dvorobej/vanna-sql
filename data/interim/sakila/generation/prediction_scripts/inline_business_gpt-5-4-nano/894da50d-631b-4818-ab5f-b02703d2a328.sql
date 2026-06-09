SELECT AVG(mc.month_total_amount)
     FROM monthly_activity mc
     WHERE mc.customer_id = ma.customer_id
       AND mc.month_start < ma.month_start
    ) AS prev_avg_amount
  FROM monthly_activity ma
),
suspicious_months AS (
  SELECT
    ms.customer_id,
    ms.customer_first_name,
    ms.customer_last_name,
    ms.customer_country,
    ms.customer_city,
    ms.month_start,
    ms.payment_count,
    ms.month_total_amount,
    ms.max_payment,
    ms.off_market_share,
    (ms.month_total_amount - ms.prev_avg_amount) AS deviation_amount,
    (ms.month_total_amount / NULLIF(ms.prev_avg_amount, 0)) AS ratio_to_prev_avg
  FROM monthly_scored ms
  WHERE ms.payment_count >= 5
    AND ms.prev_avg_amount > 0
    AND ms.month_total_amount > 3.0 * ms.prev_avg_amount
),
customer_month_categories AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    ca.g01 AS category_name,
    SUM(pb.payment_amount) AS category_amount,
    SUM(pb.payment_amount) * 1.0 / NULLIF(sm.month_total_amount, 0) AS category_share
  FROM suspicious_months sm
  JOIN payments_base pb
    ON pb.customer_id = sm.customer_id
   AND pb.month_start = sm.month_start
  JOIN ren r
    ON r.q01 = pb.rental_id
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flm f
    ON f.i01 = i.n02
  JOIN flc fcat
    ON fcat.l01 = f.i01
  JOIN cat ca
    ON ca.g01 = fcat.l02
  GROUP BY
    sm.customer_id,
    sm.month_start,
    ca.g01,
    sm.month_total_amount
),
top_categories AS (
  SELECT
    cmc.customer_id,
    cmc.month_start,
    GROUP_CONCAT(cmc.category_name, ', ') AS categories_by_share_top
  FROM (
    SELECT
      customer_id,
      month_start,
      category_name,
      category_share,
      ROW_NUMBER() OVER (
        PARTITION BY customer_id, month_start
        ORDER BY category_share DESC, category_name
      ) AS rn
    FROM customer_month_categories
  ) cmc
  WHERE cmc.rn <= 5
  GROUP BY
    cmc.customer_id,
    cmc.month_start
),
customer_month_rank AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    RANK() OVER (
      PARTITION BY sm.customer_id
      ORDER BY sm.month_total_amount DESC
    ) AS month_spend_rank_within_customer
  FROM suspicious_months sm
)
SELECT
  sm.customer_id,
  sm.customer_first_name,
  sm.customer_last_name,
  sm.customer_country,
  sm.customer_city,
  strftime('%Y-%m', sm.month_start) AS month,
  ROUND(sm.month_total_amount, 2) AS month_total_amount,
  sm.payment_count,
  ROUND(sm.off_market_share, 4) AS off_market_share,
  ROUND(sm.max_payment, 2) AS max_payment,
  cmr.month_spend_rank_within_customer AS month_spend_rank_within_customer,
  COALESCE(tc.categories_by_share_top, '') AS top_categories_by_cost_share
FROM suspicious_months sm
JOIN customer_month_rank cmr
  ON cmr.customer_id = sm.customer_id
 AND cmr.month_start = sm.month_start
LEFT JOIN top_categories tc
  ON tc.customer_id = sm.customer_id
 AND tc.month_start = sm.month_start
ORDER BY
  sm.customer_country,
  sm.customer_city,
  sm.customer_id,
  sm.month_start;