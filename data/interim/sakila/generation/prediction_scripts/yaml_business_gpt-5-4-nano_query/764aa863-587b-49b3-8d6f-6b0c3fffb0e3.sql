SELECT p04 FROM pay WHERE p01 = pb.payment_id)
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat
    ON cat.g01 = fc.l02
),
payments_monthly_categories AS (
  SELECT
    pwc.customer_id,
    pwc.country_id,
    pwc.city_name,
    pwc.month_start,
    COUNT(DISTINCT pwc.staff_id) AS distinct_staff_count_check,
    COUNT(DISTINCT CASE WHEN pwc.issuing_store_id <> pwc.home_store_id THEN pwc.payment_id END) AS off_home_payment_count,
    COUNT(CASE WHEN pwc.issuing_store_id <> pwc.home_store_id THEN 1 END) AS off_home_payment_rows,
    COUNT(DISTINCT pwc.category_id) AS distinct_category_count
  FROM payments_with_store_and_category AS pwc
  GROUP BY
    pwc.customer_id,
    pwc.country_id,
    pwc.city_name,
    pwc.month_start
),
monthly_with_prev3 AS (
  SELECT
    pm.*,
    pmc.distinct_category_count,
    pmc.off_home_payment_rows,
    pmc.distinct_staff_count_check,
    AVG(pm.month_amount) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev3_month_avg_amount
  FROM payments_monthly AS pm
  JOIN payments_monthly_categories AS pmc
    ON pmc.customer_id = pm.customer_id
   AND pmc.country_id = pm.country_id
   AND pmc.city_name = pm.city_name
   AND pmc.month_start = pm.month_start
)
SELECT
  mwp.month_start AS month,
  mwp.country_id,
  ctry.country_name AS country,
  mwp.city_name AS city,
  ROUND(mwp.month_amount, 2) AS payment_sum,
  mwp.payment_count,
  ROUND(mwp.max_single_payment, 2) AS max_single_payment,
  ROUND(1.0 * mwp.off_home_payment_rows / NULLIF(mwp.payment_count, 0), 4) AS off_home_store_payment_share,
  RANK() OVER (
    PARTITION BY mwp.country_id, mwp.month_start
    ORDER BY mwp.month_amount DESC
  ) AS customer_month_amount_rank
FROM monthly_with_prev3 AS mwp
JOIN cnt AS ctry
  ON ctry.c01 = mwp.country_id
WHERE mwp.payment_count > 0
  AND mwp.prev3_month_avg_amount IS NOT NULL
  AND mwp.prev3_month_avg_amount > 0
  AND mwp.month_amount > 3.0 * mwp.prev3_month_avg_amount
  AND mwp.distinct_staff_count_check >= 2
  AND mwp.distinct_category_count >= 3
ORDER BY
  month,
  mwp.country_id,
  mwp.customer_month_amount_rank,
  mwp.customer_id;