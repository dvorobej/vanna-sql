WITH payments_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p05 AS amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    st.o07 AS staff_store_id,
    c.h02 AS customer_home_store_id,
    cn.c02 AS country_name,
    ct.d02 AS city_name,
    CASE
      WHEN st.o07 <> c.h02 THEN 1
      ELSE 0
    END AS is_outside_home_store,
    i.n01 AS inventory_id,
    i.n02 AS film_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS st
    ON st.o01 = p.p03
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  WHERE p.p06 >= '2004-01-01'
),
monthly_customer_base AS (
  SELECT
    customer_id,
    month_start,
    country_name,
    city_name,
    COUNT(payment_id) AS payment_count,
    SUM(amount) AS monthly_amount,
    MAX(amount) AS max_payment,
    COUNT(DISTINCT staff_id) AS staff_count,
    SUM(is_outside_home_store) * 1.0 / NULLIF(COUNT(payment_id), 0) AS outside_home_store_share
  FROM payments_enriched
  GROUP BY
    customer_id,
    month_start,
    country_name,
    city_name
),
monthly_with_prev_avg AS (
  SELECT
    mcb.*,
    AVG(mcb.monthly_amount) OVER (
      PARTITION BY mcb.customer_id
      ORDER BY mcb.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_amount
  FROM monthly_customer_base AS mcb
),
customer_month_categories AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    pe.country_name,
    pe.city_name,
    COUNT(DISTINCT flc.l02) AS category_count
  FROM payments_enriched AS pe
  JOIN flc
    ON flc.l01 = pe.film_id
  WHERE pe.film_id IS NOT NULL
  GROUP BY
    pe.customer_id,
    pe.month_start,
    pe.country_name,
    pe.city_name
)
SELECT
  mwpa.month_start AS month,
  mwpa.country_name AS country,
  mwpa.city_name AS city,
  ROUND(mwpa.monthly_amount, 2) AS monthly_amount,
  mwpa.payment_count,
  ROUND(mwpa.max_payment, 2) AS max_payment,
  ROUND(mwpa.outside_home_store_share, 4) AS outside_home_store_share,
  RANK() OVER (
    PARTITION BY mwpa.country_name, mwpa.month_start
    ORDER BY mwpa.monthly_amount DESC
  ) AS country_month_rank
FROM monthly_with_prev_avg AS mwpa
JOIN customer_month_categories AS cmc
  ON cmc.customer_id = mwpa.customer_id
 AND cmc.month_start = mwpa.month_start
 AND cmc.country_name = mwpa.country_name
 AND cmc.city_name = mwpa.city_name
WHERE mwpa.avg_prev_3_months_amount IS NOT NULL
  AND mwpa.monthly_amount > 3.0 * mwpa.avg_prev_3_months_amount
  AND mwpa.staff_count >= 2
  AND cmc.category_count >= 3
ORDER BY
  mwpa.month_start,
  mwpa.country_name,
  country_month_rank,
  mwpa.customer_id;