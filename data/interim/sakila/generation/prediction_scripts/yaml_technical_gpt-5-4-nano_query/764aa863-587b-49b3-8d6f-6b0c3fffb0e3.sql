WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_amount,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT CASE WHEN stf.o01 <> cus.h02 THEN p.p03 END) AS distinct_staff_off_home_count
  FROM pay AS p
  JOIN cus
    ON cus.h01 = p.p02
  JOIN stf
    ON stf.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    ct.d02 AS city_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
),
monthly_rentals_categories AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(DISTINCT cat.g01) AS distinct_categories_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  JOIN cat
    ON cat.g01 = fc.l02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_monthly_joined AS (
  SELECT
    mp.customer_id,
    mp.month_start,
    cg.country_name,
    cg.city_name,
    mp.payment_count,
    mp.month_amount,
    mp.max_payment,
    cg.home_store_id,
    mp.distinct_staff_count,
    mp.distinct_staff_off_home_count,
    COALESCE(mrc.distinct_categories_count, 0) AS distinct_categories_count
  FROM monthly_pay AS mp
  JOIN customer_geo AS cg
    ON cg.customer_id = mp.customer_id
  LEFT JOIN monthly_rentals_categories AS mrc
    ON mrc.customer_id = mp.customer_id
   AND mrc.month_start = mp.month_start
),
monthly_with_prev AS (
  SELECT
    cmj.*,
    AVG(cmj.month_amount) OVER (
      PARTITION BY cmj.customer_id
      ORDER BY cmj.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3_months_avg_amount,
    COUNT(*) OVER (
      PARTITION BY cmj.customer_id
      ORDER BY cmj.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3_months_count
  FROM customer_monthly_joined AS cmj
),
rent_payments_denom AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CASE WHEN stf.o01 <> cus.h02 THEN 1 ELSE 0 END) AS off_home_store_payments_count,
    COUNT(*) AS payments_count
  FROM pay AS p
  JOIN cus
    ON cus.h01 = p.p02
  JOIN stf
    ON stf.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
final_set AS (
  SELECT
    mwp.customer_id,
    mwp.country_name,
    mwp.city_name,
    mwp.month_start,
    mwp.month_amount,
    mwp.payment_count,
    mwp.max_payment,
    1.0 * rpd.off_home_store_payments_count / NULLIF(rpd.payments_count, 0) AS off_home_store_payment_share,
    RANK() OVER (
      PARTITION BY mwp.country_name, mwp.month_start
      ORDER BY mwp.month_amount DESC
    ) AS country_month_amount_rank
  FROM monthly_with_prev AS mwp
  JOIN rent_payments_denom AS rpd
    ON rpd.customer_id = mwp.customer_id
   AND rpd.month_start = mwp.month_start
  WHERE mwp.prev_3_months_count = 3
    AND mwp.prev_3_months_avg_amount > 0
    AND mwp.month_amount > 3.0 * mwp.prev_3_months_avg_amount
    AND mwp.distinct_staff_count >= 2
    AND mwp.distinct_categories_count >= 3
)
SELECT
  strftime('%Y-%m', month_start) AS payment_month,
  country_name AS country,
  city_name AS city,
  ROUND(month_amount, 2) AS month_amount,
  payment_count,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(off_home_store_payment_share, 4) AS off_home_store_payment_share,
  country_month_amount_rank
FROM final_set
ORDER BY
  payment_month,
  country,
  country_month_amount_rank,
  month_amount DESC,
  customer_id;