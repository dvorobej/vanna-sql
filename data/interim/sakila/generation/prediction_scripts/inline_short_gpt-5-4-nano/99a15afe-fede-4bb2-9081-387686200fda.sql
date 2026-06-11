WITH
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
payments_base AS (
  SELECT
    p.p04 AS rental_id,
    r.q04 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p01 AS payment_id,
    p.p03 AS staff_id
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
),
rental_store AS (
  SELECT
    r.q01 AS rental_id,
    i.n03 AS store_id,
    r.q06 AS staff_return_id
  FROM ren AS r
  JOIN inv AS i ON i.n01 = r.q03
),
payments_enriched AS (
  SELECT
    pb.month_start,
    cg.country_name,
    cg.city_name,
    rs.store_id,
    pb.customer_id,
    pb.payment_id,
    pb.payment_amount,
    pb.staff_id
  FROM payments_base AS pb
  JOIN rental_store AS rs ON rs.rental_id = pb.rental_id
  JOIN customer_geo AS cg ON cg.customer_id = pb.customer_id
),
monthly_agg AS (
  SELECT
    month_start,
    country_name,
    city_name,
    store_id,
    customer_id,
    COUNT(payment_id) AS payment_count,
    SUM(payment_amount) AS payment_sum,
    COUNT(DISTINCT staff_id) AS distinct_staff_count
  FROM payments_enriched
  GROUP BY
    month_start, country_name, city_name, store_id, customer_id
),
monthly_with_prev_avg AS (
  SELECT
    ma.*,
    AVG(payment_sum) OVER (
      PARTITION BY customer_id, store_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_amount
  FROM monthly_agg AS ma
),
store_country_client_stats AS (
  SELECT
    mwpa.*,
    PERCENT_RANK() OVER (
      PARTITION BY store_id, country_name, month_start
      ORDER BY payment_sum DESC
    ) AS pr_top_by_client_amount
  FROM monthly_with_prev_avg AS mwpa
),
monthly_overdue_returns AS (
  SELECT
    date(r.q05, 'start of month') AS month_start,
    cg.country_name,
    cg.city_name,
    i.n03 AS store_id,
    r.q04 AS customer_id,
    SUM(CASE WHEN r.q05 IS NOT NULL AND r.q05 > r.q02 THEN 1 ELSE 0 END) AS overdue_return_count,
    COUNT(*) AS rental_count
  FROM ren AS r
  JOIN inv AS i ON i.n01 = r.q03
  JOIN cus AS c ON c.h01 = r.q04
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
  JOIN customer_geo AS cg ON cg.customer_id = c.h01
  GROUP BY
    date(r.q05, 'start of month'),
    cg.country_name, cg.city_name, i.n03, r.q04
),
final_join AS (
  SELECT
    sccs.month_start,
    sccs.country_name,
    sccs.city_name,
    sccs.store_id,
    sccs.customer_id,
    sccs.payment_sum,
    sccs.payment_count,
    sccs.distinct_staff_count,
    COALESCE(
      1.0 * mor.overdue_return_count / NULLIF(mor.rental_count, 0),
      0.0
    ) AS overdue_return_share,
    sccs.pr_top_by_client_amount AS client_amount_rank_by_store_country
  FROM store_country_client_stats AS sccs
  LEFT JOIN monthly_overdue_returns AS mor
    ON mor.month_start = sccs.month_start
   AND mor.country_name = sccs.country_name
   AND mor.city_name = sccs.city_name
   AND mor.store_id = sccs.store_id
   AND mor.customer_id = sccs.customer_id
)
SELECT
  country_name,
  city_name,
  store_id AS store,
  strftime('%Y-%m', month_start) AS month,
  ROUND(payment_sum, 2) AS rental_payment_sum,
  payment_count,
  distinct_staff_count AS staff_count,
  ROUND(overdue_return_share, 4) AS overdue_return_share,
  client_amount_rank_by_store_country AS amount_rank
FROM final_join
WHERE
  avg_prev_amount IS NOT NULL
  AND avg_prev_amount > 0
  AND payment_sum > 3.0 * avg_prev_amount
  AND client_amount_rank_by_store_country <= 0.05
ORDER BY
  month_start,
  country_name,
  store_id,
  payment_sum DESC,
  customer_id;