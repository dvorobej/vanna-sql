WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    r.q01 AS rental_id_check,

    /* customer geo */
    cu.h06 AS customer_address_id,
    adr_c.e05 AS customer_city_id,
    cn_c.d02 AS customer_city,
    cnt_c.c02 AS customer_country,

    /* staff/store geo (сотрудник, принявший платеж) */
    st.o07 AS staff_store_id,
    stf_adr.e05 AS staff_city_id,
    cnt_s.d02 AS staff_city,
    cnt_s.c02 AS staff_country,

    /* film categories for this payment via rental->inventory->film->film_category */
    fc.l02 AS category_id
  FROM pay p
  JOIN cus cu ON cu.h01 = p.p02
  LEFT JOIN adr adr_c ON adr_c.e01 = cu.h06
  LEFT JOIN cty cn_c ON cn_c.d01 = adr_c.e05
  LEFT JOIN cnt cnt_c ON cnt_c.c01 = cn_c.d03

  JOIN stf st ON st.o01 = p.p03
  LEFT JOIN adr stf_adr ON stf_adr.e01 = st.o04
  LEFT JOIN cty cnt_s ON cnt_s.d01 = stf_adr.e05
  LEFT JOIN cnt ON cnt.c01 = cnt_s.d03

  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN flc fc ON fc.l01 = i.n02
  WHERE p.p04 IS NOT NULL
),
monthly_customer_store_mismatch AS (
  SELECT
    customer_id,
    month_start,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_total_amount,
    MAX(payment_amount) AS max_payment,
    SUM(
      CASE
        WHEN staff_city_id <> customer_city_id THEN 1
        WHEN staff_country <> customer_country THEN 1
        ELSE 0
      END
    ) * 1.0 / COUNT(*) AS foreign_shop_payment_share,
    GROUP_CONCAT(DISTINCT category_id) AS category_ids_csv
  FROM payment_enriched
  GROUP BY customer_id, month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(month_total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount
  FROM monthly_customer_store_mismatch mc
),
ranked_months_within_customer AS (
  SELECT
    mwh.*,
    RANK() OVER (
      PARTITION BY customer_id
      ORDER BY month_total_amount DESC
    ) AS month_amount_rank_within_customer
  FROM monthly_with_history mwh
),
eligible_months AS (
  SELECT
    rmc.*
  FROM ranked_months_within_customer rmc
  WHERE prev_avg_month_amount IS NOT NULL
    AND prev_avg_month_amount > 0
    AND month_total_amount > 3.0 * prev_avg_month_amount
    AND payment_count >= 5
),
eligible_customers AS (
  /* ensure employees were from different stores AND mismatch condition exists in month rows */
  SELECT
    p.customer_id,
    e.month_start,
    COUNT(DISTINCT p.staff_store_id) AS distinct_staff_stores_in_month
  FROM eligible_months e
  JOIN payment_enriched p
    ON p.customer_id = e.customer_id
   AND p.month_start = e.month_start
  GROUP BY p.customer_id, e.month_start
  HAVING COUNT(DISTINCT p.staff_store_id) >= 2
),
main AS (
  SELECT
    e.customer_id,
    e.month_start,
    e.month_total_amount,
    e.payment_count,
    e.foreign_shop_payment_share,
    e.max_payment,
    e.month_amount_rank_within_customer,
    e.category_ids_csv
  FROM eligible_months e
  JOIN eligible_customers ec
    ON ec.customer_id = e.customer_id
   AND ec.month_start = e.month_start
)
SELECT
  m.month_start AS month,
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  cn.country_name AS customer_country,
  cn.city_name AS customer_city,
  m.month_total_amount AS total_payment_amount,
  m.payment_count AS payment_count,
  ROUND(m.foreign_shop_payment_share, 4) AS foreign_shop_payment_share,
  m.max_payment AS max_payment,
  m.month_amount_rank_within_customer AS month_rank_within_customer,
  GROUP_CONCAT(DISTINCT cat.g02) AS top_categories
FROM main m
JOIN cus c ON c.h01 = m.customer_id
LEFT JOIN adr a ON a.e01 = c.h06
LEFT JOIN cty cn_city ON cn_city.d01 = a.e05
LEFT JOIN cnt cn_cnt ON cn_cnt.c01 = cn_city.d03
LEFT JOIN cnt cn ON cn.c01 = cn_cnt.c01

/* map category ids to category names */
LEFT JOIN payment_enriched pe
  ON pe.customer_id = m.customer_id
 AND pe.month_start = m.month_start
LEFT JOIN cat cat
  ON cat.g01 = pe.category_id
GROUP BY
  m.month_start,
  c.h01,
  customer_name,
  customer_country,
  customer_city,
  m.month_total_amount,
  m.payment_count,
  m.foreign_shop_payment_share,
  m.max_payment,
  m.month_amount_rank_within_customer
ORDER BY
  m.month_start,
  m.month_total_amount DESC,
  m.customer_id;