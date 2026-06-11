WITH monthly_customer_pay AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_home_store_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_amount,
    MAX(p.p05) AS max_single_payment,
    SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS off_store_payment_share,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_staff_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    c.h01,
    c.h02,
    date(p.p06, 'start of month')
),
monthly_with_history AS (
  SELECT
    m.*,
    AVG(m.month_amount) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount
  FROM monthly_customer_pay AS m
),
qualified_months AS (
  SELECT
    mwh.*
  FROM monthly_with_history AS mwh
  WHERE mwh.prev_months_avg_amount IS NOT NULL
    AND mwh.payment_count >= 5
    AND mwh.month_amount > 3.0 * mwh.prev_months_avg_amount
),
payment_copy_geo AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    r.q06 AS store_id_copy,
    a.e01 AS customer_address_id,
    cty_c.d01 AS customer_city_id,
    cnt_c.c01 AS customer_country_id,
    cty_s.d01 AS copy_city_id,
    cnt_s.c01 AS copy_country_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cty_c
    ON cty_c.d01 = a.e05
  JOIN cnt AS cnt_c
    ON cnt_c.c01 = cty_c.d03
  JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN adr AS a_s
    ON a_s.e01 = r.q06
  LEFT JOIN cty AS cty_s
    ON cty_s.d01 = a_s.e05
  LEFT JOIN cnt AS cnt_s
    ON cnt_s.c01 = cty_s.d03
),
qualified_months_store_geo AS (
  SELECT
    qm.customer_id,
    qm.month_start,
    qm.off_store_payment_share,
    qm.month_amount,
    qm.payment_count,
    qm.max_single_payment,
    qm.customer_home_store_id,
    -- наличие разных городов или стран "копии" и клиента
    MAX(CASE
          WHEN pcg.customer_city_id IS NULL OR pcg.copy_city_id IS NULL THEN 0
          WHEN pcg.customer_city_id <> pcg.copy_city_id
            OR pcg.customer_country_id <> pcg.copy_country_id
          THEN 1
          ELSE 0
        END) AS has_city_or_country_diff,
    -- проверка "разные сотрудники разных магазинов" через ren.q06 / stf.o07
    MAX(CASE
          WHEN s.o07 <> qm.customer_home_store_id THEN 1
          ELSE 0
        END) AS has_off_store_staff_payment
  FROM qualified_months AS qm
  LEFT JOIN payment_copy_geo AS pcg
    ON pcg.customer_id = qm.customer_id
   AND pcg.month_start = qm.month_start
  LEFT JOIN pay AS p
    ON p.p02 = qm.customer_id
   AND date(p.p06, 'start of month') = qm.month_start
  LEFT JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    qm.customer_id,
    qm.month_start,
    qm.off_store_payment_share,
    qm.month_amount,
    qm.payment_count,
    qm.max_single_payment,
    qm.customer_home_store_id
  HAVING
    has_city_or_country_diff = 1
),
monthly_categories AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    GROUP_CONCAT(DISTINCT cat.g02) AS categories_list
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat
    ON cat.g01 = fc.l02
  WHERE cat.g02 IS NOT NULL
    AND i.n02 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
ranked_in_customer AS (
  SELECT
    qmsg.*,
    RANK() OVER (
      PARTITION BY qmsg.customer_id
      ORDER BY qmsg.month_amount DESC
    ) AS month_amount_rank_within_customer
  FROM qualified_months_store_geo AS qmsg
)
SELECT
  rig.customer_id AS h01,
  strftime('%Y-%m', rig.month_start) AS month,
  ROUND(rig.month_amount, 2) AS month_amount,
  rig.payment_count,
  ROUND(rig.off_store_payment_share, 4) AS off_store_payment_share,
  ROUND(rig.max_single_payment, 2) AS max_single_payment,
  rig.month_amount_rank_within_customer,
  mc.categories_list AS categories_list
FROM ranked_in_customer AS rig
LEFT JOIN monthly_categories AS mc
  ON mc.customer_id = rig.customer_id
 AND mc.month_start = rig.month_start
ORDER BY
  rig.customer_id,
  rig.month_start,
  rig.month_amount DESC;