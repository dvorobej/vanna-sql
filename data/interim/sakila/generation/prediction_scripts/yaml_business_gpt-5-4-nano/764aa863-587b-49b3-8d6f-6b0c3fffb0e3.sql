WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS customer_home_store_id,
    ctg.l02 AS category_id,
    CASE
      WHEN sf.o07 <> c.h02 THEN 1
      ELSE 0
    END AS is_off_home_store
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS sf
    ON sf.o01 = p.p03
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS ctg
    ON ctg.l01 = i.n02
),
monthly_customer AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    MAX(pe.country_id) AS dummy_country_id,
    COUNT(*) AS payment_count,
    SUM(pe.amount) AS month_amount,
    MAX(pe.amount) AS max_payment,
    SUM(pe.is_off_home_store) * 1.0 / COUNT(*) AS off_home_store_share,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pe.category_id) AS distinct_category_count
  FROM (
    SELECT
      pe0.*,
      cnt.c01 AS country_id
    FROM payment_enriched AS pe0
    JOIN adr AS a
      ON a.e01 = pe0.customer_id
    LEFT JOIN cty AS ci
      ON ci.d01 = a.e05
    LEFT JOIN cnt
      ON cnt.c01 = ci.d03
  ) AS pe
  GROUP BY
    pe.customer_id,
    pe.month_start
),
monthly_with_prev3 AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev3_months_avg_amount
  FROM monthly_customer AS mc
),
qualifying_months AS (
  SELECT
    *
  FROM monthly_with_prev3
  WHERE prev3_months_avg_amount IS NOT NULL
    AND prev3_months_avg_amount > 0
    AND month_amount > 3.0 * prev3_months_avg_amount
    AND distinct_staff_count >= 2
    AND distinct_category_count >= 3
),
ranked_in_country AS (
  SELECT
    qm.*,
    cnt.c01 AS country_id,
    RANK() OVER (
      PARTITION BY cnt.c01, qm.month_start
      ORDER BY qm.month_amount DESC
    ) AS country_month_amount_rank
  FROM qualifying_months AS qm
  JOIN cus AS c
    ON c.h01 = qm.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ci.d03
)
SELECT
  ric.month_start,
  ric.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  cnt.c02 AS customer_country,
  city.d02 AS customer_city,
  ROUND(ric.month_amount, 2) AS month_amount,
  ric.payment_count,
  ROUND(ric.max_payment, 2) AS max_payment,
  ROUND(ric.off_home_store_share, 4) AS off_home_store_payment_share,
  ric.country_month_amount_rank
FROM ranked_in_country AS ric
JOIN cus AS c
  ON c.h01 = ric.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS city
  ON city.d01 = a.e05
JOIN cnt
  ON cnt.c01 = city.d03
WHERE 1 = 1
ORDER BY
  ric.month_start,
  ric.country_month_amount_rank,
  ric.month_amount DESC;