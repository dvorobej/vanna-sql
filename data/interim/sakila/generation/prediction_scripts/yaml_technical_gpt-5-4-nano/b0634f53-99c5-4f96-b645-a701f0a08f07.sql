WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS customer_country
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
daily_pay AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT inv.n03) AS store_count,
    GROUP_CONCAT(DISTINCT cnt_store.c02) AS store_countries_list,
    SUM(CASE WHEN cnt_store.c02 <> cg.customer_country THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS share_payments_from_other_countries,
    SUM(CASE WHEN cnt_store.c02 <> cg.customer_country THEN 1 ELSE 0 END) AS other_country_payment_count
  FROM pay AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.p02
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = r.q03
  LEFT JOIN sto AS s
    ON s.j01 = inv.n03
  LEFT JOIN adr AS a_store
    ON a_store.e01 = s.j03
  LEFT JOIN cty AS ci_store
    ON ci_store.d01 = a_store.e05
  LEFT JOIN cnt AS cnt_store
    ON cnt_store.c01 = ci_store.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    DATE(p.p06)
),
daily_with_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp2.day_amount)
      FROM daily_pay AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_day >= DATE(dp.payment_day, '-30 days')
        AND dp2.payment_day < dp.payment_day
    ) AS avg_prev_30d_amount
  FROM daily_pay AS dp
),
suspicious AS (
  SELECT
    dwa.*,
    CAST(dwa.day_amount AS REAL) / NULLIF(dwa.avg_prev_30d_amount, 0) AS exceed_ratio
  FROM daily_with_avg AS dwa
  WHERE dwa.avg_prev_30d_amount IS NOT NULL
    AND dwa.avg_prev_30d_amount > 0
    AND dwa.payment_count >= 3
    AND dwa.day_amount >= 2 * dwa.avg_prev_30d_amount
    AND dwa.other_country_payment_count >= 1
),
ranked AS (
  SELECT
    s.*,
    cg.customer_country,
    RANK() OVER (
      PARTITION BY cg.customer_country
      ORDER BY s.exceed_ratio DESC, s.day_amount DESC, s.customer_id, s.payment_day
    ) AS suspicion_rank_in_country
  FROM suspicious AS s
  JOIN customer_geo AS cg
    ON cg.customer_id = s.customer_id
)
SELECT
  r.customer_id,
  r.customer_country,
  r.payment_day AS payment_date,
  r.payment_count,
  ROUND(r.day_amount, 2) AS day_amount,
  ROUND(r.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
  r.staff_count,
  r.store_count,
  r.store_countries_list,
  r.suspicion_rank_in_country
FROM ranked AS r
ORDER BY
  r.customer_country,
  r.suspicion_rank_in_country,
  r.payment_day,
  r.customer_id;