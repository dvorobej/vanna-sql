WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c01 AS customer_country_id,
    cnt.c02 AS customer_country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS cnt ON cnt.c01 = ci.d03
),
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    cg.customer_name,
    cg.customer_country_id,
    cg.customer_country_name,
    DATE(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count,
    GROUP_CONCAT(DISTINCT cnt_s.c02) AS store_countries,
    SUM(CASE WHEN cnt_s.c01 <> cg.customer_country_id THEN 1 ELSE 0 END) AS payments_in_other_country_count,
    COUNT(*) AS day_payments_count_for_other_country
  FROM pay AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.p02
  JOIN stf AS s
    ON s.o01 = p.p03
  LEFT JOIN sto AS sto
    ON sto.j01 = s.o07
  LEFT JOIN adr AS adr_s
    ON adr_s.e01 = sto.k06
  LEFT JOIN cty AS ci_s
    ON ci_s.d01 = adr_s.e05
  LEFT JOIN cnt AS cnt_s
    ON cnt_s.c01 = ci_s.d03
  GROUP BY
    p.p02,
    cg.customer_name,
    cg.customer_country_id,
    cg.customer_country_name,
    DATE(p.p06)
),
with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp_prev.day_amount)
      FROM daily_payments AS dp_prev
      WHERE dp_prev.customer_id = dp.customer_id
        AND dp_prev.payment_date >= date(dp.payment_date, '-30 day')
        AND dp_prev.payment_date < dp.payment_date
    ) AS avg_day_amount_prev_30d
  FROM daily_payments AS dp
),
ranked AS (
  SELECT
    wh.*,
    DENSE_RANK() OVER (
      PARTITION BY wh.customer_country_id
      ORDER BY (wh.day_amount / NULLIF(wh.avg_day_amount_prev_30d, 0)) DESC, wh.day_amount DESC
    ) AS suspicion_rank_in_country
  FROM with_history AS wh
)
SELECT
  r.customer_id,
  r.customer_name,
  r.customer_country_name AS customer_country,
  r.payment_date,
  r.payment_count,
  ROUND(r.day_amount, 2) AS day_amount,
  ROUND(r.avg_day_amount_prev_30d, 2) AS avg_day_amount_prev_30d,
  r.distinct_staff_count,
  r.distinct_store_count,
  r.store_countries,
  r.suspicion_rank_in_country
FROM ranked AS r
WHERE r.avg_day_amount_prev_30d IS NOT NULL
  AND r.avg_day_amount_prev_30d > 0
  AND r.payment_count >= 3
  AND r.day_amount >= 2.0 * r.avg_day_amount_prev_30d
  AND r.payments_in_other_country_count >= 1
ORDER BY
  r.customer_country,
  r.suspicion_rank_in_country,
  r.day_amount DESC,
  r.payment_date,
  r.customer_id;