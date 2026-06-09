WITH pay_2000 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rent_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount_real
  FROM pay p
  WHERE p.p06 IS NOT NULL
),
rent_inv AS (
  SELECT
    r.q01 AS rent_id,
    r.q04 AS customer_id,
    r.q03 AS inv_id,
    r.q06 AS staff_id
  FROM ren r
),
inv_film AS (
  SELECT
    i.n01 AS inv_id,
    i.n02 AS film_id
  FROM inv i
),
film_cats AS (
  SELECT
    fc.l01 AS film_id,
    fc.l02 AS category_id
  FROM flc fc
),
staff_home AS (
  SELECT
    s.o01 AS staff_id,
    s.o07 AS store_id
  FROM stf s
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
),
store_geo AS (
  -- Требуется, чтобы city/country магазина отличались от city/country адреса клиента.
  SELECT
    st.j01 AS store_id,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name
  FROM sto st
  JOIN adr a ON a.e01 = st.j02
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
),
base_pay AS (
  SELECT
    p.month_start,
    p.customer_id,
    p.payment_id,
    p.staff_id,
    p.rent_id,
    p.payment_amount_real
  FROM pay_2000 p
  WHERE p.rent_id IS NOT NULL
),
base_pay_enriched AS (
  SELECT
    bp.month_start,
    bp.customer_id,
    bp.payment_id,
    bp.staff_id,
    bp.payment_amount_real,
    sh.store_id AS paying_store_id,
    cgeo.city_id AS customer_city_id,
    cgeo.country_id AS customer_country_id,
    sgeo.city_id AS paying_city_id,
    sgeo.country_id AS paying_country_id,
    r.q03 AS inv_id
  FROM base_pay bp
  JOIN ren r ON r.q01 = bp.rent_id
  JOIN staff_home sh ON sh.staff_id = bp.staff_id
  JOIN customer_geo cgeo ON cgeo.customer_id = bp.customer_id
  JOIN store_geo sgeo ON sgeo.store_id = sh.store_id
),
pay_with_customer_store_diff AS (
  SELECT
    bpe.*,
    CASE
      WHEN bpe.customer_city_id <> bpe.paying_city_id
        OR bpe.customer_country_id <> bpe.paying_country_id
      THEN 1 ELSE 0
    END AS is_foreign_store_by_city_or_country
  FROM base_pay_enriched bpe
),
monthly_pay AS (
  SELECT
    month_start,
    customer_id,
    COUNT(*) AS payment_count,
    SUM(payment_amount_real) AS month_total_amount,
    SUM(CASE WHEN is_foreign_store_by_city_or_country = 1 THEN 1 ELSE 0 END) AS foreign_store_payment_count,
    MAX(payment_amount_real) AS max_single_payment
  FROM pay_with_customer_store_diff
  GROUP BY
    month_start,
    customer_id
),
monthly_with_prev AS (
  SELECT
    mp.*,
    AVG(mp.month_total_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount
  FROM monthly_pay mp
),
qualified_customers_months AS (
  SELECT
    mwp.*,
    RANK() OVER (
      PARTITION BY mwp.customer_id
      ORDER BY mwp.month_total_amount DESC
    ) AS month_rank_within_customer
  FROM monthly_with_prev mwp
  WHERE
    mwp.prev_avg_month_amount IS NOT NULL
    AND mwp.payment_count >= 5
    AND mwp.month_total_amount > 3.0 * mwp.prev_avg_month_amount
),
-- Ограничение "платежи проходили через сотрудников разных магазинов"
-- + платежи именно через "чужие" магазины (город/страна отличались).
monthly_staff_store_counts AS (
  SELECT
    month_start,
    customer_id,
    COUNT(DISTINCT paying_store_id) AS distinct_paying_store_count,
    COUNT(DISTINCT CASE WHEN is_foreign_store_by_city_or_country = 1 THEN paying_store_id END) AS distinct_foreign_store_count
  FROM pay_with_customer_store_diff
  GROUP BY
    month_start,
    customer_id
),
qualified_months_final AS (
  SELECT
    qcm.*,
    msc.distinct_paying_store_count,
    msc.distinct_foreign_store_count
  FROM qualified_customers_months qcm
  JOIN monthly_staff_store_counts msc
    ON msc.month_start = qcm.month_start
   AND msc.customer_id = qcm.customer_id
  WHERE
    msc.distinct_paying_store_count >= 2
    AND msc.distinct_foreign_store_count >= 1
),
-- Для списка категорий: "на основную часть расходов" интерпретируем как топ-N категорий по сумме платежей (в месяце/клиенте).
-- Т.к. оплату нельзя напрямую связать с конкретной категорией без связки rent->inv->film->cat,
-- сопоставим категорию по фильму из аренды, привязанной к платежу.
payment_item_category_amount AS (
  SELECT
    pws.month_start,
    pws.customer_id,
    fc.category_id,
    SUM(pws.payment_amount_real) AS category_amount
  FROM pay_with_customer_store_diff pws
  JOIN inv_film iff ON iff.inv_id = pws.inv_id
  JOIN film_cats fc ON fc.film_id = iff.film_id
  GROUP BY
    pws.month_start,
    pws.customer_id,
    fc.category_id
),
category_top_list AS (
  SELECT
    qmf.month_start,
    qmf.customer_id,
    GROUP_CONCAT(category_id, ', ') AS top_categories
  FROM (
    SELECT
      qm.month_start,
      qm.customer_id,
      pica.category_id,
      pica.category_amount,
      SUM(pica.category_amount) OVER (
        PARTITION BY qm.month_start, qm.customer_id
        ORDER BY pica.category_amount DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS running_sum,
      SUM(pica.category_amount) OVER (
        PARTITION BY qm.month_start, qm.customer_id
      ) AS total_sum
    FROM qualified_months_final qm
    JOIN payment_item_category_amount pica
      ON pica.month_start = qm.month_start
     AND pica.customer_id = qm.customer_id
  ) ranked
  WHERE ranked.running_sum <= ranked.total_sum * 0.8
  GROUP BY
    month_start,
    customer_id
)
SELECT
  qmf.customer_id,
  CAST(strftime('%Y-%m', qmf.month_start) AS TEXT) AS month,
  qmf.month_total_amount AS month_total_amount,
  qmf.payment_count AS payment_count,
  ROUND(1.0 * qmf.foreign_store_payment_count / NULLIF(qmf.payment_count, 0), 4) AS foreign_store_payment_share,
  qmf.max_single_payment AS max_single_payment,
  qmf.month_rank_within_customer AS month_rank_within_customer,
  ctl.top_categories AS main_spending_categories
FROM qualified_months_final qmf
LEFT JOIN category_top_list ctl
  ON ctl.month_start = qmf.month_start
 AND ctl.customer_id = qmf.customer_id
ORDER BY
  qmf.month_start,
  qmf.customer_id;