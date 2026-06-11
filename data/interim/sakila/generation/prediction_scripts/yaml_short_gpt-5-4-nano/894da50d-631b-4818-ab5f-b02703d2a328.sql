WITH RECURSIVE months(month_start) AS (
  SELECT date('2005-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    stf.o07 AS staff_store_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    i.n02 AS film_id
  FROM pay AS p
  JOIN stf AS stf
    ON stf.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
),
customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    adr.e05 AS customer_city_id,
    adr.e01 AS customer_address_id,
    c.h02 AS customer_store_id,
    cnt.c01 AS customer_country_id,
    cnt.c02 AS customer_country_name
  FROM cus AS c
  JOIN adr AS adr
    ON adr.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = adr.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
),
monthly_payment AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    SUM(pe.payment_amount) AS month_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT pe.staff_id) AS staff_count,
    COUNT(DISTINCT pe.staff_store_id) AS staff_store_count,
    MAX(pe.payment_amount) AS max_payment,
    SUM(CASE WHEN pe.staff_store_id <> cb.customer_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS alien_store_share
  FROM payment_enriched AS pe
  JOIN customer_base AS cb
    ON cb.customer_id = pe.customer_id
  WHERE pe.month_start >= (SELECT date('2005-01-01'))
    AND pe.month_start <  (SELECT date('2006-01-01'))
  GROUP BY
    pe.customer_id,
    pe.month_start
),
city_country_mismatch AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    SUM(
      CASE
        WHEN cs_ct.d01 <> st_ct.d01 OR cs_cnt.c02 <> st_cnt.c02 THEN 1
        ELSE 0
      END
    ) * 1.0 / COUNT(*) AS alien_city_or_country_share
  FROM payment_enriched AS pe
  JOIN cus AS c
    ON c.h01 = pe.customer_id
  JOIN adr AS cs_adr
    ON cs_adr.e01 = c.h06
  JOIN cty AS cs_ct
    ON cs_ct.d01 = cs_adr.e05
  JOIN cnt AS cs_cnt
    ON cs_cnt.c01 = cs_ct.d03
  JOIN sto AS st
    ON st.j01 = pe.staff_store_id
  JOIN adr AS st_adr
    ON st_adr.e01 = st.k04
  JOIN cty AS st_ct
    ON st_ct.d01 = st_adr.e05
  JOIN cnt AS st_cnt
    ON st_cnt.c01 = st_ct.d03
  WHERE pe.month_start >= (SELECT date('2005-01-01'))
    AND pe.month_start <  (SELECT date('2006-01-01'))
  GROUP BY
    pe.customer_id,
    pe.month_start
),
monthly_with_avg AS (
  SELECT
    mp.*,
    (
      SELECT AVG(m2.month_amount)
      FROM monthly_payment AS m2
      WHERE m2.customer_id = mp.customer_id
        AND m2.month_start < mp.month_start
    ) AS prev_months_avg_amount
  FROM monthly_payment AS mp
),
qualified AS (
  SELECT
    mwa.customer_id,
    mwa.month_start,
    mwa.month_amount,
    mwa.payment_count,
    mwa.alien_store_share,
    mwa.max_payment,
    (mwa.month_amount - mwa.prev_months_avg_amount) AS deviation_from_prev_avg,
    (mwa.month_amount / NULLIF(mwa.prev_months_avg_amount, 0)) AS ratio_to_prev_avg,
    ROW_NUMBER() OVER (
      PARTITION BY mwa.month_start
      ORDER BY mwa.month_amount DESC, mwa.customer_id
    ) AS month_rank
  FROM monthly_with_avg AS mwa
  JOIN city_country_mismatch AS ccm
    ON ccm.customer_id = mwa.customer_id
   AND ccm.month_start = mwa.month_start
  WHERE mwa.prev_months_avg_amount IS NOT NULL
    AND mwa.payment_count >= 5
    AND mwa.staff_store_count >= 2
    AND ccm.alien_city_or_country_share > 0
    AND mwa.month_amount > 3.0 * mwa.prev_months_avg_amount
),
film_categories_per_month AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    GROUP_CONCAT(DISTINCT cat.g02) AS film_categories
  FROM payment_enriched AS pe
  LEFT JOIN flc AS fc
    ON fc.l01 = pe.film_id
  LEFT JOIN cat
    ON cat.g01 = fc.l02
  WHERE pe.month_start >= '2005-01-01'
    AND pe.month_start <  '2006-01-01'
  GROUP BY
    pe.customer_id,
    pe.month_start
)
SELECT
  q.month_start AS payment_month,
  q.month_amount AS month_sum,
  q.payment_count,
  ROUND(q.alien_store_share, 4) AS alien_store_share,
  ROUND(q.max_payment, 2) AS max_payment,
  q.month_rank AS month_rank,
  fcpd.film_categories AS film_categories_list
FROM qualified AS q
LEFT JOIN film_categories_per_month AS fcpd
  ON fcpd.customer_id = q.customer_id
 AND fcpd.month_start = q.month_start
ORDER BY
  q.month_start,
  q.month_rank;