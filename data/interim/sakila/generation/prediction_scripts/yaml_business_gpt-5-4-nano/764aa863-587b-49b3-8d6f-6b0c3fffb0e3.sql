WITH payment_details AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    stf.o07 AS staff_store_id,
    p.p05 AS amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS customer_home_store_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    city.d02 AS city_name,
    r.q03 AS inventory_id,
    inv.n02 AS film_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf
    ON stf.o01 = p.p03
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = city.d03
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv
    ON inv.n01 = r.q03
),
customer_monthly AS (
  SELECT
    pd.customer_id,
    pd.customer_name,
    pd.country_id,
    pd.country_name,
    pd.city_name,
    pd.month_start,
    COUNT(pd.payment_id) AS payment_count,
    SUM(pd.amount) AS month_total_amount,
    MAX(pd.amount) AS max_payment,
    COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
    SUM(CASE WHEN pd.staff_store_id <> pd.customer_home_store_id THEN 1 ELSE 0 END) AS off_home_store_payment_count,
    1.0 * SUM(CASE WHEN pd.staff_store_id <> pd.customer_home_store_id THEN 1 ELSE 0 END) / COUNT(pd.payment_id) AS off_home_store_payment_share,
    COUNT(DISTINCT pd.film_id) AS distinct_films_count
  FROM payment_details AS pd
  GROUP BY
    pd.customer_id,
    pd.customer_name,
    pd.country_id,
    pd.country_name,
    pd.city_name,
    pd.month_start
),
customer_monthly_with_prev AS (
  SELECT
    cm.*,
    AVG(cm.month_total_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_amount,
    COUNT(*) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3_months_available
  FROM customer_monthly AS cm
),
customer_monthly_categories AS (
  SELECT
    pd.customer_id,
    pd.month_start,
    COUNT(DISTINCT fc.l02) AS distinct_category_count
  FROM payment_details AS pd
  JOIN flc AS fc
    ON fc.l01 = pd.film_id
  GROUP BY
    pd.customer_id,
    pd.month_start
),
suspicious_months AS (
  SELECT
    cmwp.customer_id,
    cmwp.customer_name,
    cmwp.country_id,
    cmwp.country_name,
    cmwp.city_name,
    cmwp.month_start,
    cmwp.payment_count,
    cmwp.month_total_amount,
    cmwp.max_payment,
    cmwp.off_home_store_payment_share,
    cmwp.distinct_staff_count,
    cmwp.avg_prev_3_months_amount,
    cmwp.prev_3_months_available,
    cmc.distinct_category_count
  FROM customer_monthly_with_prev AS cmwp
  JOIN customer_monthly_categories AS cmc
    ON cmc.customer_id = cmwp.customer_id
   AND cmc.month_start = cmwp.month_start
  WHERE cmwp.prev_3_months_available = 3
    AND cmc.distinct_category_count >= 3
    AND cmwp.distinct_staff_count >= 2
    AND cmwp.avg_prev_3_months_amount > 0
    AND cmwp.month_total_amount > 3.0 * cmwp.avg_prev_3_months_amount
),
ranked_in_country AS (
  SELECT
    sm.*,
    RANK() OVER (
      PARTITION BY sm.country_id, sm.month_start
      ORDER BY sm.month_total_amount DESC
    ) AS country_month_payment_rank
  FROM suspicious_months AS sm
)
SELECT
  ric.customer_id,
  ric.customer_name,
  ric.country_name,
  ric.city_name,
  strftime('%Y-%m', ric.month_start) AS payment_month,
  ROUND(ric.month_total_amount, 2) AS month_total_amount,
  ric.payment_count,
  ROUND(ric.max_payment, 2) AS max_payment,
  ROUND(ric.off_home_store_payment_share, 4) AS off_home_store_payment_share,
  ric.country_month_payment_rank
FROM ranked_in_country AS ric
ORDER BY
  ric.country_name,
  ric.payment_month,
  ric.country_month_payment_rank,
  ric.month_total_amount DESC;