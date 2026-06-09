SELECT DISTINCT
    fc.l01 AS film_id,
    fc.l02 AS category_id
  FROM flc fc
),
payments_joined AS (
  SELECT
    pcg.country_name,
    pcg.city_name,
    pcg.home_store_id,
    p.payment_month,
    p.customer_id,
    p.payment_amount,
    CASE
      WHEN ca.g02 = 'Action' THEN 'Action'
      WHEN ca.g02 = 'New' THEN 'New'
      ELSE NULL
    END AS action_new_bucket,
    CASE WHEN ca.g02 = 'Action' THEN 1 ELSE 0 END AS is_action,
    CASE WHEN ca.g02 = 'New' THEN 1 ELSE 0 END AS is_new
  FROM payments_2005 p
  JOIN base_customer_geo pcg
    ON pcg.customer_id = p.customer_id
  LEFT JOIN ren r ON r.q01 = p.rental_id
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN flc fc ON fc.l01 = i.n02
  LEFT JOIN cat ca ON ca.g01 = fc.l02
),
monthly_aggr AS (
  SELECT
    country_name,
    city_name,
    home_store_id,
    payment_month,
    customer_id,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS payment_sum,
    MAX(payment_amount) AS max_payment,
    SUM(CASE WHEN is_action = 1 THEN payment_amount ELSE 0 END) AS action_sum,
    SUM(CASE WHEN is_new = 1 THEN payment_amount ELSE 0 END) AS new_sum
  FROM payments_joined
  GROUP BY
    country_name,
    city_name,
    home_store_id,
    payment_month,
    customer_id
),
monthly_aggr_final AS (
  SELECT
    ma.*,
    CASE WHEN payment_sum > 0 THEN action_sum * 1.0 / payment_sum ELSE 0 END AS action_share,
    CASE WHEN payment_sum > 0 THEN new_sum * 1.0 / payment_sum ELSE 0 END AS new_share
  FROM monthly_aggr ma
),
ranked AS (
  SELECT
    *,
    RANK() OVER (
      PARTITION BY country_name, city_name, home_store_id, payment_month
      ORDER BY payment_sum DESC
    ) AS country_city_store_month_rank
  FROM monthly_aggr_final
)
SELECT
  payment_month AS month,
  country_name AS country,
  city_name AS city,
  home_store_id AS store_id,
  customer_id,
  payment_count AS payment_count,
  ROUND(payment_sum, 2) AS payment_sum,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(action_share, 4) AS action_share,
  ROUND(new_share, 4) AS new_share,
  country_city_store_month_rank
FROM ranked
WHERE payment_count > 0
ORDER BY
  payment_month,
  country,
  city,
  store_id,
  country_city_store_month_rank,
  payment_sum DESC;