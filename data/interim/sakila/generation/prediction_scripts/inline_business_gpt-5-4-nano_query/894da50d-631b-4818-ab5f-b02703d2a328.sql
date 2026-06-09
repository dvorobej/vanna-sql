WITH payments_monthly AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    SUM(
      CASE
        WHEN r.q01 IS NOT NULL
         AND ( (c_store.h01 IS NOT NULL AND c_store.h01 <> s_store.h01) OR (c_addr_city.d02 <> s_addr_city.d02) OR (c_addr_country.d02 <> s_addr_country.d02) )
        THEN 1
        ELSE 0
      END
    ) AS foreign_store_payment_count,
    SUM(
      CASE
        WHEN r.q01 IS NULL THEN 0
        ELSE 1
      END
    ) AS paid_for_rent_payment_count
  FROM pay AS p
  JOIN cus AS c_pay ON c_pay.h01 = p.p02
  LEFT JOIN ren AS r ON r.q01 = p.p04
  LEFT JOIN inv AS i ON i.n01 = r.q03
  LEFT JOIN sto AS s_store ON s_store.j01 = i.n03
  LEFT JOIN adr AS s_addr ON s_addr.e01 = (SELECT o04 FROM stf WHERE o01 = r.q06)
  LEFT JOIN adr AS c_addr ON c_addr.e01 = c_pay.h06
  LEFT JOIN cty AS c_addr_city ON c_addr_city.d01 = c_addr.e05
  LEFT JOIN cty AS c_addr_country ON c_addr_country.d01 = c_addr_city.d03
  LEFT JOIN cty AS s_addr_city ON s_addr_city.d01 = s_addr.e05
  LEFT JOIN cty AS s_addr_country ON s_addr_country.d01 = s_addr_city.d03
  LEFT JOIN sto AS c_store ON c_store.j01 = c_pay.h02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    date(p.p06, 'start of month')
),
payments_rolling AS (
  SELECT
    pm.*,
    AVG(pm.payment_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_payment_sum
  FROM payments_monthly AS pm
),
qual_months AS (
  SELECT
    pr.customer_id,
    pr.month,
    pr.month_start,
    pr.payment_sum,
    pr.payment_count,
    pr.max_payment,
    pr.foreign_store_payment_count,
    pr.paid_for_rent_payment_count,
    pr.avg_prev_payment_sum
  FROM payments_rolling AS pr
  WHERE pr.avg_prev_payment_sum IS NOT NULL
    AND pr.payment_count >= 5
    AND pr.payment_sum > 3.0 * pr.avg_prev_payment_sum
    AND pr.foreign_store_payment_count * 1.0 / NULLIF(pr.payment_count, 0) > 0
),
rent_staff_store_by_payment AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS customer_home_store_id,
    st_store.j01 AS staff_store_id,
    city_name.d02 AS customer_city,
    st_city_name.d02 AS staff_city,
    ctry_name.c02 AS customer_country,
    st_ctry_name.c02 AS staff_country
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN ren r ON r.q01 = p.p04
  JOIN stf sf ON sf.o01 = r.q06
  JOIN sto st_store ON st_store.j01 = sf.o07
  JOIN adr adrc ON adrc.e01 = c.h06
  JOIN cty city_name ON city_name.d01 = adrc.e05
  JOIN cnt ctry_name ON ctry_name.c01 = city_name.d03
  JOIN adr adrs ON adrs.e01 = sf.o04
  JOIN cty st_city_name ON st_city_name.d01 = adrs.e05
  JOIN cnt st_ctry_name ON st_ctry_name.c01 = st_city_name.d03
),
payment_foreign_flag AS (
  SELECT
    rp.customer_id,
    rp.month_start,
    rp.payment_id,
    CASE
      WHEN (rp.customer_city <> rp.staff_city) OR (rp.customer_country <> rp.staff_country) OR (rp.customer_home_store_id <> rp.staff_store_id)
      THEN 1 ELSE 0
    END AS is_foreign_store
  FROM rent_staff_store_by_payment rp
),
foreign_share_by_month AS (
  SELECT
    pf.customer_id,
    strftime('%Y-%m', pf.month_start) AS month,
    pf.month_start,
    SUM(pf.is_foreign_store) AS foreign_store_payment_count
  FROM (
    SELECT
      pfp.customer_id,
      pfp.month_start,
      p.p01 AS payment_id,
      pfp.is_foreign_store
    FROM payment_foreign_flag pfp
    JOIN pay p ON p.p01 = pfp.payment_id
  ) pf
  GROUP BY
    pf.customer_id,
    strftime('%Y-%m', pf.month_start),
    pf.month_start
),
distinct_staff_foreign_by_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT stf.o07) AS distinct_staff_store_count
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  JOIN stf ON stf.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY p.p02, date(p.p06, 'start of month')
),
category_weights AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    ca.g01 AS category_id,
    SUM(CAST(p.p05 AS REAL)) AS category_spend
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flc fc ON fc.l01 = i.n02
  JOIN cat ca ON ca.g01 = fc.l02
  WHERE p.p04 IS NOT NULL
  GROUP BY p.p02, date(p.p06, 'start of month'), ca.g01
),
top_categories AS (
  SELECT
    cw.customer_id,
    cw.month_start,
    GROUP_CONCAT(cat.i02, ', ') AS top_categories
  FROM (
    SELECT
      customer_id,
      month_start,
      category_id,
      category_spend,
      SUM(category_spend) OVER (PARTITION BY customer_id, month_start) AS total_spend,
      category_spend * 1.0 / NULLIF(SUM(category_spend) OVER (PARTITION BY customer_id, month_start), 0) AS category_share,
      ROW_NUMBER() OVER (PARTITION BY customer_id, month_start ORDER BY category_spend DESC) AS rn
    FROM category_weights
  ) cw
  JOIN cat ON cat.g01 = cw.category_id
  WHERE cw.rn <= 3
  GROUP BY cw.customer_id, cw.month_start
),
monthly_rank_within_customer AS (
  SELECT
    q.customer_id,
    q.month_start,
    RANK() OVER (
      PARTITION BY q.customer_id
      ORDER BY q.payment_sum DESC
    ) AS month_payment_rank_within_customer
  FROM qual_months q
)
SELECT
  q.month,
  q.customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  q.payment_sum,
  q.payment_count,
  CAST(q.foreign_store_payment_count AS REAL) / NULLIF(q.payment_count, 0) AS foreign_store_payment_share,
  q.max_payment,
  mr.month_payment_rank_within_customer,
  tc.top_categories AS top_categories_by_spend
FROM qual_months q
JOIN cus c ON c.h01 = q.customer_id
JOIN distinct_staff_foreign_by_month ds
  ON ds.customer_id = q.customer_id
 AND ds.month_start = q.month_start
LEFT JOIN top_categories tc
  ON tc.customer_id = q.customer_id
 AND tc.month_start = q.month_start
JOIN monthly_rank_within_customer mr
  ON mr.customer_id = q.customer_id
 AND mr.month_start = q.month_start
WHERE ds.distinct_staff_count >= 2
  AND ds.distinct_staff_store_count >= 2
ORDER BY q.month_start, q.payment_sum DESC, q.customer_id;