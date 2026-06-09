WITH payment_monthly AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_sum,
    MAX(p.p05) AS max_payment
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
payment_with_prev AS (
  SELECT
    pm.*,
    AVG(pm.month_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_sum
  FROM payment_monthly AS pm
),
candidate_months AS (
  SELECT
    pwp.customer_id,
    pwp.month_start,
    pwp.payment_count,
    pwp.month_sum,
    pwp.max_payment,
    pwp.prev_avg_month_sum
  FROM payment_with_prev AS pwp
  WHERE pwp.prev_avg_month_sum IS NOT NULL
    AND pwp.payment_count >= 5
    AND pwp.month_sum > 3.0 * pwp.prev_avg_month_sum
),
payment_detailed AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    st.o07 AS staff_store_id,
    c.h06 AS customer_address_id,
    -- География клиента
    ct_c.d02 AS customer_city,
    cn_c.c02 AS customer_country,
    -- География магазина по сотруднику
    ct_s.d02 AS staff_city,
    cn_s.c02 AS staff_country,
    r.q01 AS rental_id,
    i.n01 AS inventory_id,
    fc.l02 AS category_id
  FROM pay AS p
  JOIN candidate_months AS cm
    ON cm.customer_id = p.p02
   AND cm.month_start = strftime('%Y-%m', p.p06)
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS adr_c
    ON adr_c.e01 = c.h06
  JOIN cty AS ct_c
    ON ct_c.d01 = adr_c.e05
  JOIN cnt AS cn_c
    ON cn_c.c01 = ct_c.d03
  LEFT JOIN stf AS st
    ON st.o01 = p.p03
  LEFT JOIN sto AS so_s
    ON so_s.j01 = st.o07
  LEFT JOIN adr AS adr_s
    ON adr_s.e01 = so_s.j02
  LEFT JOIN cty AS ct_s
    ON ct_s.d01 = adr_s.e05
  LEFT JOIN cnt AS cn_s
    ON cn_s.c01 = ct_s.d03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flc AS fc
    ON fc.l01 = i.n02
),
summary_cross_store AS (
  SELECT
    pd.customer_id,
    pd.month_start,
    SUM(
      CASE
        WHEN pd.customer_city IS NOT NULL
         AND pd.staff_city IS NOT NULL
         AND (pd.customer_city <> pd.staff_city OR pd.customer_country <> pd.staff_country)
        THEN 1
        ELSE 0
      END
    ) * 1.0 / COUNT(*) AS off_store_ops_share,
    COUNT(*) AS month_payment_count_check,
    SUM(pd.payment_amount) AS month_sum_check
  FROM payment_detailed AS pd
  GROUP BY
    pd.customer_id,
    pd.month_start
),
category_top AS (
  SELECT
    pd.customer_id,
    pd.month_start,
    pd.category_id,
    SUM(pd.payment_amount) AS category_sum,
    ROW_NUMBER() OVER (
      PARTITION BY pd.customer_id, pd.month_start
      ORDER BY SUM(pd.payment_amount) DESC
    ) AS rn
  FROM payment_detailed AS pd
  GROUP BY
    pd.customer_id,
    pd.month_start,
    pd.category_id
)
SELECT
  cm.customer_id,
  (cu.h03 || ' ' || cu.h04) AS customer_name,
  cu_country.c02 AS customer_country,
  cu_city.d02 AS customer_city,
  cm.month_start AS month,
  ROUND(cm.month_sum, 2) AS month_sum,
  cm.payment_count,
  ROUND(scs.off_store_ops_share, 4) AS off_store_ops_share,
  ROUND(cm.max_payment, 2) AS max_payment,
  RANK() OVER (
    PARTITION BY cm.customer_id
    ORDER BY cm.month_sum DESC
  ) AS month_rank_within_customer,
  GROUP_CONCAT(
    DISTINCT
      ca.category_id || ':' || ROUND(ca.category_sum, 2)
  ) AS top_categories_by_spend
FROM candidate_months AS cm
JOIN cus AS cu
  ON cu.h01 = cm.customer_id
LEFT JOIN adr AS adr_cu
  ON adr_cu.e01 = cu.h06
LEFT JOIN cty AS cu_city
  ON cu_city.d01 = adr_cu.e05
LEFT JOIN cnt AS cu_country
  ON cu_country.c01 = cu_city.d03
JOIN summary_cross_store AS scs
  ON scs.customer_id = cm.customer_id
 AND scs.month_start = cm.month_start
LEFT JOIN (
  SELECT customer_id, month_start, category_id, category_sum
  FROM category_top
  WHERE rn <= 5
) AS ca
  ON ca.customer_id = cm.customer_id
 AND ca.month_start = cm.month_start
GROUP BY
  cm.customer_id,
  customer_name,
  customer_country,
  customer_city,
  cm.month_start,
  cm.month_sum,
  cm.payment_count,
  scs.off_store_ops_share,
  cm.max_payment
ORDER BY
  cm.month_start,
  cm.month_sum DESC,
  cm.customer_id;