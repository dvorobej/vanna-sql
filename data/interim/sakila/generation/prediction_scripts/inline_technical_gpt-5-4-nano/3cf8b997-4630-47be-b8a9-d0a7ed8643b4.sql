WITH bounds AS (
    SELECT
      date('2005-01-01') AS min_month,
      date('2005-12-01') AS max_month
  )
  SELECT min_month AS month_start
  FROM bounds
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < (SELECT max_month FROM bounds)
),
payment_lines AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,     -- cus.h01
    p.p03 AS staff_id,        -- stf.o01
    p.p05 AS payment_amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    p.p04 AS rental_id        -- ren.q01
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
payments_with_rental AS (
  SELECT
    pl.customer_id,
    pl.staff_id,
    pl.payment_amount,
    pl.month_start,
    r.q01 AS rental_id,
    r.q04 AS rental_customer_id,
    CASE
      WHEN r.q01 IS NOT NULL AND r.q04 IS NOT NULL AND r.q01 = pl.rental_id
      THEN 1
      ELSE 0
    END AS has_linked_rental
  FROM payment_lines pl
  LEFT JOIN ren r
    ON r.q01 = pl.rental_id
  WHERE r.q01 IS NOT NULL
    AND r.q04 IS NOT NULL
),
monthly_customer_store AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    m.month_start,
    COUNT(pwr.payment_id) AS payment_count,
    SUM(pwr.payment_amount) AS month_amount
  FROM cus c
  CROSS JOIN months m
  LEFT JOIN (
    SELECT
      pr.customer_id,
      pr.payment_amount,
      pr.month_start,
      pl.payment_id
    FROM payments_with_rental pr
    JOIN payment_lines pl
      ON pl.customer_id = pr.customer_id
     AND pl.month_start = pr.month_start
  ) pwr
    ON pwr.customer_id = c.h01
   AND pwr.month_start = m.month_start
  GROUP BY
    c.h01, c.h02, customer_name, m.month_start
),
monthly_with_sma AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_month_avg
  FROM monthly_customer_store mc
),
sus_months AS (
  SELECT
    mws.*,
    (mws.month_amount - mws.prev_2_month_avg) AS deviation_from_sma,
    (mws.month_amount / NULLIF(mws.prev_2_month_avg, 0)) AS ratio_to_sma
  FROM monthly_with_sma mws
  WHERE mws.prev_2_month_avg IS NOT NULL
    AND mws.payment_count >= 3
    AND mws.month_amount >= 2.0 * mws.prev_2_month_avg
),
monthly_top_staff AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY c.h01, c.h02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM cus c
  JOIN pay p
    ON p.p02 = c.h01
   AND p.p06 >= '2005-01-01'
   AND p.p06 <  '2006-01-01'
  JOIN ren r
    ON r.q01 = p.p04
   AND r.q04 = p.p02
   AND r.q01 IS NOT NULL
  GROUP BY
    c.h01, c.h02, date(p.p06, 'start of month'), p.p03
),
monthly_staff_pick AS (
  SELECT
    mts.customer_id,
    mts.store_id,
    mts.month_start,
    mts.staff_id
  FROM monthly_top_staff mts
  WHERE mts.rn = 1
),
store_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    adr.e05 AS city_id,
    ct.d02 AS city_name,
    adr.e01 AS customer_address_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name
  FROM cus c
  JOIN adr
    ON adr.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = adr.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
),
sus_months_enriched AS (
  SELECT
    sm.customer_id,
    sm.customer_name,
    sm.store_id,
    sm.month_start,
    sm.payment_count,
    sm.month_amount,
    sm.prev_2_month_avg,
    sm.deviation_from_sma,
    sm.ratio_to_sma,
    s.j01 AS shop_id,
    s.j02 AS shop_manager_id,
    sg.country_id,
    sg.country_name,
    sg.city_id,
    sg.city_name,
    adr.e01 AS address_id,
    adr.e05 AS address_city_id,
    stf.o01 AS staff_id,
    stf.o02 AS staff_first_name,
    stf.o03 AS staff_last_name
  FROM sus_months sm
  JOIN sto s
    ON s.j01 = sm.store_id
  JOIN store_geo sg
    ON sg.customer_id = sm.customer_id
   AND sg.store_id = sm.store_id
  JOIN adr
    ON adr.e01 = (SELECT h06 FROM cus c2 WHERE c2.h01 = sm.customer_id LIMIT 1)
  LEFT JOIN monthly_staff_pick msp
    ON msp.customer_id = sm.customer_id
   AND msp.store_id = sm.store_id
   AND msp.month_start = sm.month_start
  LEFT JOIN stf
    ON stf.o01 = msp.staff_id
),
store_susp_totals AS (
  SELECT
    smae.store_id,
    smae.customer_id,
    SUM(smae.month_amount) AS suspicious_total_amount
  FROM sus_months_enriched smae
  GROUP BY smae.store_id, smae.customer_id
),
store_susp_ranked AS (
  SELECT
    sst.*,
    COUNT(*) OVER (PARTITION BY sst.store_id) AS store_customer_count,
    RANK() OVER (PARTITION BY sst.store_id ORDER BY sst.suspicious_total_amount DESC, sst.customer_id) AS store_customer_rank,
    NTILE(10) OVER (PARTITION BY sst.store_id ORDER BY sst.suspicious_total_amount DESC) AS store_ntile10
  FROM store_susp_totals sst
),
top_10pct_customers AS (
  SELECT
    store_id,
    customer_id
  FROM store_susp_ranked
  WHERE store_ntile10 = 1
),
final_selection AS (
  SELECT
    smae.customer_id,
    smae.customer_name,
    smae.store_id,
    smae.country_id,
    smae.country_name,
    smae.city_id,
    smae.city_name,
    smae.month_start AS payment_month,
    smae.payment_count,
    ROUND(smae.month_amount, 2) AS month_amount,
    ROUND(smae.prev_2_month_avg, 2) AS prev_2_month_avg,
    ROUND(smae.deviation_from_sma, 2) AS deviation_from_sma,
    smae.ratio_to_sma AS ratio_to_sma,
    smae.staff_id AS top_staff_id,
    smae.staff_first_name,
    smae.staff_last_name
  FROM sus_months_enriched smae
  JOIN top_10pct_customers t
    ON t.store_id = smae.store_id
   AND t.customer_id = smae.customer_id
)
SELECT *
FROM final_selection
ORDER BY
  store_id,
  country_id,
  payment_month,
  month_amount DESC,
  customer_id;