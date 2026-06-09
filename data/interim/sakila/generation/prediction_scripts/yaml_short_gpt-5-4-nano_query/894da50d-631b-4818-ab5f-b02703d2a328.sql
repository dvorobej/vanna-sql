WITH payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
payment_with_prev_avg AS (
  SELECT
    pm.*,
    AVG(pm.payment_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_payment_sum
  FROM payment_monthly AS pm
),
eligible_months AS (
  SELECT *
  FROM payment_with_prev_avg
  WHERE prev_avg_payment_sum > 0
    AND payment_count >= 5
    AND payment_sum > 3.0 * prev_avg_payment_sum
),
payment_with_geo_and_store_cmp AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    cu.h02 AS customer_home_store_id,
    s.o07 AS staff_store_id,
    a.e05 AS customer_city_id,
    a.e01 AS customer_address_id,
    ci.d03 AS customer_country_id,
    st.city_id AS staff_city_id,
    st.country_id AS staff_country_id,
    r.q01 AS rental_id,
    i.n02 AS film_id
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  JOIN cus cu ON cu.h01 = p.p02
  JOIN adr a ON a.e01 = cu.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN stf s ON s.o01 = p.p03
  JOIN (
    SELECT
      st2.j01 AS store_id,
      a2.e05 AS city_id,
      c2.d03 AS country_id
    FROM sto st2
    JOIN adr a2 ON a2.e01 = st2.k06
    JOIN cty c2 ON c2.d01 = a2.e05
  ) AS st ON st.store_id = s.o07
  JOIN inv i ON i.n01 = r.q03
),
monthly_foreign_share AS (
  SELECT
    pw.customer_id,
    pw.month_start,
    COUNT(*) AS payment_count,
    SUM(pw.payment_amount) AS payment_sum,
    SUM(
      CASE
        WHEN pw.staff_store_id <> pw.customer_home_store_id
          OR pw.staff_city_id <> pw.customer_city_id
          OR pw.staff_country_id <> pw.customer_country_id
        THEN 1 ELSE 0
      END
    ) AS foreign_store_payment_count
  FROM payment_with_geo_and_store_cmp pw
  GROUP BY pw.customer_id, pw.month_start
),
top_cat_by_spend AS (
  SELECT
    pf.customer_id,
    pf.month_start,
    ca.g02 AS category_name,
    SUM(pf.payment_amount) AS spend_amount,
    RANK() OVER (
      PARTITION BY pf.customer_id, pf.month_start
      ORDER BY SUM(pf.payment_amount) DESC
    ) AS cat_rank
  FROM payment_with_geo_and_store_cmp pf
  JOIN flc fc ON fc.l01 = pf.film_id
  JOIN cat ca ON ca.g01 = fc.l02
  GROUP BY
    pf.customer_id,
    pf.month_start,
    ca.g02
),
category_list AS (
  SELECT
    t.customer_id,
    t.month_start,
    GROUP_CONCAT(t.category_name, ', ') AS main_categories
  FROM top_cat_by_spend t
  WHERE t.cat_rank <= 3
  GROUP BY t.customer_id, t.month_start
),
client_month_result AS (
  SELECT
    em.customer_id,
    em.month_start,
    em.payment_sum,
    em.payment_count,
    em.max_payment,
    mf.foreign_store_payment_count,
    1.0 * mf.foreign_store_payment_count / NULLIF(mf.payment_count, 0) AS foreign_store_payment_share
  FROM eligible_months em
  JOIN monthly_foreign_share mf
    ON mf.customer_id = em.customer_id
   AND mf.month_start = em.month_start
)
SELECT
  cmr.customer_id,
  strftime('%Y-%m', cmr.month_start) AS month,
  ROUND(cmr.payment_sum, 2) AS total_payment_sum,
  cmr.payment_count,
  ROUND(cmr.foreign_store_payment_share, 4) AS foreign_store_payment_share,
  ROUND(cmr.max_payment, 2) AS largest_payment,
  RANK() OVER (
    PARTITION BY cmr.customer_id
    ORDER BY cmr.payment_sum DESC
  ) AS month_rank_within_customer,
  cl.main_categories AS top_categories_main_spend
FROM client_month_result cmr
LEFT JOIN category_list cl
  ON cl.customer_id = cmr.customer_id
 AND cl.month_start = cmr.month_start
ORDER BY
  cmr.customer_id,
  cmr.month_start;