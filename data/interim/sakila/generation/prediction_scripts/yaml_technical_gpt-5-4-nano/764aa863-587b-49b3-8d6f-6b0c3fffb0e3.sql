WITH monthly_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    c.h06 AS customer_address_id,
    ct.country_id,
    ct.country_name,
    city.city_id,
    city.city_name,
    date(p.p06, 'start of month') AS month_start,

    p.p03 AS staff_id,

    p.p05 AS payment_amount,

    CASE
      WHEN inv_store.j01 IS NOT NULL AND inv_store.j01 <> c.h02 THEN 1
      ELSE 0
    END AS is_not_home_store_payment,

    CASE
      WHEN p.p04 IS NOT NULL THEN 1
      ELSE 0
    END AS has_rental,

    flc.cat_id
  FROM cus AS c
  JOIN adr AS adr
    ON adr.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = adr.e05
  JOIN cnt AS ct
    ON ct.c01 = city.d03
  JOIN pay AS p
    ON p.p02 = c.h01
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS inv
    ON inv.n01 = r.q03
  JOIN sto AS inv_store
    ON inv_store.j01 = inv.n03
  JOIN flm AS f
    ON f.i01 = inv.n02
  JOIN flc AS flc
    ON flc.l01 = f.i01
  WHERE p.p04 IS NOT NULL
),
monthly_customer_stats AS (
  SELECT
    mb.customer_id,
    mb.country_id,
    mb.country_name,
    mb.city_id,
    mb.city_name,
    mb.month_start,

    SUM(mb.payment_amount) AS month_payment_sum,
    COUNT(*) AS month_payment_count,
    MAX(mb.payment_amount) AS max_single_payment,

    SUM(mb.is_not_home_store_payment) * 1.0 / COUNT(*) AS not_home_store_payment_share,

    COUNT(DISTINCT mb.staff_id) AS distinct_staff_count
  FROM monthly_base AS mb
  GROUP BY
    mb.customer_id,
    mb.country_id,
    mb.country_name,
    mb.city_id,
    mb.city_name,
    mb.month_start
),
monthly_with_prev_avg AS (
  SELECT
    mcs.*,
    AVG(mcs.month_payment_sum) OVER (
      PARTITION BY mcs.customer_id
      ORDER BY mcs.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3_months_avg_sum
  FROM monthly_customer_stats AS mcs
),
eligible_customer_months AS (
  SELECT
    mwp.*
  FROM monthly_with_prev_avg AS mwp
  WHERE mwp.prev_3_months_avg_sum IS NOT NULL
    AND mwp.month_payment_sum > mwp.prev_3_months_avg_sum * 3.0
),
eligible_customer_months_staff AS (
  SELECT
    ecm.customer_id,
    ecm.country_id,
    ecm.country_name,
    ecm.city_id,
    ecm.city_name,
    ecm.month_start,
    ecm.month_payment_sum,
    ecm.month_payment_count,
    ecm.max_single_payment,
    ecm.not_home_store_payment_share,
    ecm.distinct_staff_count
  FROM eligible_customer_months AS ecm
  WHERE ecm.distinct_staff_count >= 2
),
category_coverage AS (
  SELECT
    mb.customer_id,
    mb.country_id,
    mb.country_name,
    mb.city_id,
    mb.city_name,
    mb.month_start,
    COUNT(DISTINCT mb.cat_id) AS distinct_category_count
  FROM (
    SELECT
      c.h01 AS customer_id,
      c.h02 AS home_store_id,
      ct.country_id,
      ct.country_name,
      city.city_id,
      city.city_name,
      date(p.p06, 'start of month') AS month_start,
      p.p03 AS staff_id,
      p.p05 AS payment_amount,
      CASE
        WHEN inv_store.j01 IS NOT NULL AND inv_store.j01 <> c.h02 THEN 1
        ELSE 0
      END AS is_not_home_store_payment,
      flc.l02 AS cat_id
    FROM cus AS c
    JOIN adr AS adr
      ON adr.e01 = c.h06
    JOIN cty AS city
      ON city.d01 = adr.e05
    JOIN cnt AS ct
      ON ct.c01 = city.d03
    JOIN pay AS p
      ON p.p02 = c.h01
    JOIN ren AS r
      ON r.q01 = p.p04
    JOIN inv AS inv
      ON inv.n01 = r.q03
    JOIN sto AS inv_store
      ON inv_store.j01 = inv.n03
    JOIN flm AS f
      ON f.i01 = inv.n02
    JOIN flc AS flc
      ON flc.l01 = f.i01
    WHERE p.p04 IS NOT NULL
  ) AS mb
  GROUP BY
    mb.customer_id,
    mb.country_id,
    mb.country_name,
    mb.city_id,
    mb.city_name,
    mb.month_start
),
final_eligible AS (
  SELECT
    ecms.customer_id,
    ecms.country_id,
    ecms.country_name,
    ecms.city_id,
    ecms.city_name,
    ecms.month_start,
    ecms.month_payment_sum,
    ecms.month_payment_count,
    ecms.max_single_payment,
    ecms.not_home_store_payment_share
  FROM eligible_customer_months_staff AS ecms
  JOIN category_coverage AS cc
    ON cc.customer_id = ecms.customer_id
   AND cc.country_id = ecms.country_id
   AND cc.city_id = ecms.city_id
   AND cc.month_start = ecms.month_start
  WHERE cc.distinct_category_count >= 3
),
ranked AS (
  SELECT
    fe.*,
    RANK() OVER (
      PARTITION BY fe.country_id, fe.month_start
      ORDER BY fe.month_payment_sum DESC
    ) AS customer_rank_in_country
  FROM final_eligible AS fe
)
SELECT
  month_start AS month,
  country_name AS c02,
  city_name AS d02,
  SUM(month_payment_sum) AS payment_sum,
  SUM(month_payment_count) AS payment_count,
  MAX(max_single_payment) AS max_single_payment,
  SUM(month_payment_count * not_home_store_payment_share) * 1.0 / NULLIF(SUM(month_payment_count), 0) AS not_home_store_payment_share,
  customer_rank_in_country
FROM ranked
GROUP BY
  month_start,
  country_name,
  city_name,
  customer_rank_in_country
ORDER BY
  month,
  c02,
  d02,
  payment_sum DESC,
  customer_rank_in_country;