WITH
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    st.j01 AS home_store_id,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    co.c01 AS country_id
  FROM cus AS c
  JOIN sto AS st
    ON st.j01 = c.h02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
rental_store_id AS (
  SELECT
    r.q01 AS rental_id,
    i.n03 AS rental_store_id
  FROM ren AS r
  JOIN inv AS i
    ON i.n01 = r.q03
),
payments_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    rs.rental_store_id,
    rg.home_store_id,
    rg.country_id,
    rg.country_name,
    rg.city_name,
    p.p04 AS rental_id,
    CASE
      WHEN r.q05 IS NULL THEN 0
      WHEN r.q05 > datetime(r.q02, printf('+%d days', f.i07)) THEN 1
      ELSE 0
    END AS returned_late_flag
  FROM pay AS p
  JOIN rental_store_id AS rs
    ON rs.rental_id = p.p04
  JOIN customer_geo AS rg
    ON rg.customer_id = p.p02
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flm AS f
    ON f.i01 = i.n02
),
monthly_customer_store AS (
  SELECT
    pe.customer_id,
    pe.home_store_id,
    pe.country_id,
    pe.country_name,
    pe.city_name,
    pe.rental_store_id AS store_id,
    pe.month_start,
    COUNT(*) AS payment_count,
    SUM(pe.payment_amount) AS payment_sum,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    AVG(CASE WHEN pe.returned_late_flag = 1 THEN 1.0 ELSE 0.0 END) AS returned_late_share
  FROM payments_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.home_store_id,
    pe.country_id,
    pe.country_name,
    pe.city_name,
    pe.rental_store_id,
    pe.month_start
),
monthly_scored AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months_sum
  FROM monthly_customer_store AS mc
),
country_store_rank AS (
  SELECT
    ms.*,
    PERCENT_RANK() OVER (
      PARTITION BY ms.home_store_id, ms.country_id, ms.month_start
      ORDER BY ms.payment_sum DESC
    ) AS pct_rank_desc
  FROM monthly_scored AS ms
)
SELECT
  c.customer_id,
  c.first_name,
  c.last_name,
  c.country_name,
  c.city_name,
  c.store_id AS store_id,
  strftime('%Y-%m', c.month_start) AS payment_month,
  ROUND(c.payment_sum, 2) AS payment_sum,
  c.payment_count,
  c.distinct_staff_count,
  ROUND(c.returned_late_share, 4) AS returned_late_share,
  RANK() OVER (
    PARTITION BY c.store_id, c.month_start
    ORDER BY c.payment_sum DESC
  ) AS store_month_payment_rank
FROM (
  SELECT
    mcs.customer_id,
    rg.first_name,
    rg.last_name,
    mcs.home_store_id,
    mcs.country_id,
    mcs.country_name,
    mcs.city_name,
    mcs.store_id,
    mcs.month_start,
    mcs.payment_sum,
    mcs.payment_count,
    mcs.distinct_staff_count,
    mcs.returned_late_share,
    mcs.personal_avg_prev_months_sum,
    ms.pct_rank_desc
  FROM monthly_scored AS mcs
  JOIN customer_geo AS rg
    ON rg.customer_id = mcs.customer_id
  JOIN country_store_rank AS ms
    ON ms.customer_id = mcs.customer_id
   AND ms.store_id = mcs.store_id
   AND ms.month_start = mcs.month_start
   AND ms.country_id = mcs.country_id
   AND ms.home_store_id = mcs.home_store_id
  WHERE mcs.personal_avg_prev_months_sum IS NOT NULL
) AS c
WHERE
  c.payment_sum >= 3.0 * c.personal_avg_prev_months_sum
  AND c.pct_rank_desc <= 0.05
ORDER BY
  c.month_start,
  c.store_id,
  c.payment_sum DESC,
  c.customer_id;