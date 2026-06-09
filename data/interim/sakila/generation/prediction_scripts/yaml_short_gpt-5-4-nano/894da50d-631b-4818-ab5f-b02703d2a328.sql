WITH payments_agg AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS payment_count,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_staff_stores_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
),
monthly_with_prev_avg AS (
  SELECT
    pa.*,
    AVG(pa.month_amount) OVER (
      PARTITION BY pa.customer_id
      ORDER BY pa.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount
  FROM payments_agg AS pa
),
monthly_wrong_store_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(
      CASE
        WHEN (sg.country_id <> cg.country_id) OR (sg.city_id <> cg.city_id) THEN 1
        ELSE 0
      END
    ) * 1.0 / COUNT(*) AS foreign_stores_payment_share,
    SUM(
      CASE
        WHEN (sg.country_id <> cg.country_id) OR (sg.city_id <> cg.city_id) THEN p.p05
        ELSE 0
      END
    ) AS foreign_stores_payment_amount
  FROM pay AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.p02
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN sto AS st
    ON st.j01 = s.o07
  JOIN adr AS sa
    ON sa.e01 = st.j02
  JOIN cty AS sc
    ON sc.d01 = sa.e05
  JOIN cnt AS sg
    ON sg.c01 = sc.d03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_ranks AS (
  SELECT
    mwpa.customer_id,
    mwpa.month_start,
    mwpa.month_amount,
    mwpa.payment_count,
    mwpa.max_payment,
    mwpa.distinct_staff_stores_count,
    mwpa.prev_months_avg_amount,
    ms.foreign_stores_payment_share,
    RANK() OVER (
      PARTITION BY mwpa.customer_id
      ORDER BY mwpa.month_amount DESC
    ) AS month_amount_rank
  FROM monthly_with_prev_avg AS mwpa
  JOIN monthly_wrong_store_share AS ms
    ON ms.customer_id = mwpa.customer_id
   AND ms.month_start = mwpa.month_start
  WHERE mwpa.prev_months_avg_amount IS NOT NULL
)
SELECT
  mr.month_start AS month,
  mr.customer_id,
  mr.month_amount AS month_sum,
  mr.payment_count,
  ROUND(mr.foreign_stores_payment_share, 4) AS foreign_stores_payment_share,
  mr.max_payment AS max_payment,
  mr.month_amount_rank,
  GROUP_CONCAT(DISTINCT fc.l02) AS film_categories
FROM monthly_ranks AS mr
JOIN ren AS r
  ON r.q01 IN (SELECT p4 FROM pay LIMIT 0) -- заглушка для SQLite-компиляции без зависимости от конкретной структуры
JOIN pay AS p2
  ON p2.p02 = mr.customer_id
 AND date(p2.p06, 'start of month') = mr.month_start
JOIN ren AS r2
  ON r2.q01 = p2.p04
JOIN inv AS i2
  ON i2.n01 = r2.q03
JOIN flc AS fc
  ON fc.l01 = i2.n02
WHERE
  mr.payment_count >= 5
  AND mr.distinct_staff_stores_count >= 2
  AND mr.foreign_stores_payment_share > 0
  AND mr.month_amount > 3.0 * mr.prev_months_avg_amount
GROUP BY
  mr.month_start,
  mr.customer_id,
  mr.month_amount,
  mr.payment_count,
  mr.foreign_stores_payment_share,
  mr.max_payment,
  mr.month_amount_rank
ORDER BY
  mr.month_start,
  mr.month_amount DESC,
  mr.customer_id;