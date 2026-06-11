WITH
-- платежи 2000..9999 не ограничиваем, считаем "в любом календарном месяце" на всей шкале данных
payments_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount
  FROM pay AS p
),
customer_month_pay AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    COUNT(*) AS payment_count,
    SUM(pe.payment_amount) AS month_total_amount,
    MAX(pe.payment_amount) AS max_payment_amount
  FROM payments_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.month_start
),
customer_month_history AS (
  SELECT
    cmp.*,
    AVG(cmp.month_total_amount) OVER (
      PARTITION BY cmp.customer_id
      ORDER BY cmp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount
  FROM customer_month_pay AS cmp
),
-- для условий "платежи через разных магазинов" и "город/страна адреса != город/страна магазина-копии"
payment_to_store_geo AS (
  SELECT
    pe.customer_id,
    pe.month_start,
    pe.payment_id,
    pe.payment_amount,
    s_store.j01 AS payment_store_id,
    cs_city.d02 AS customer_city,
    cs_ctry.c02 AS customer_country,
    s_city.d02 AS store_city,
    s_ctry.c02 AS store_country,
    i.n02 AS film_id
  FROM payments_enriched AS pe
  JOIN ren AS r ON r.q01 = pe.rental_id
  JOIN inv AS i ON i.n01 = r.q03
  JOIN sto AS s_store ON s_store.j01 = i.n03
  JOIN cus AS c ON c.h01 = pe.customer_id
  JOIN adr AS ca ON ca.e01 = c.h06
  JOIN cty AS cs_city ON cs_city.d01 = ca.e05
  JOIN cnt AS cs_ctry ON cs_ctry.c01 = cs_city.d03
  JOIN adr AS sa ON sa.e01 = s_store.j02
  JOIN cty AS s_city ON s_city.d01 = sa.e05
  JOIN cnt AS s_ctry ON s_ctry.c01 = s_city.d03
),
month_customer_geo_splits AS (
  SELECT
    pg.customer_id,
    pg.month_start,
    SUM(CASE WHEN pg.payment_store_id IS NOT NULL THEN 1 ELSE 0 END) AS total_payment_rows,
    SUM(CASE
          WHEN (pg.customer_city <> pg.store_city) OR (pg.customer_country <> pg.store_country)
          THEN 1 ELSE 0
        END) AS foreign_store_payment_rows,
    SUM(pg.payment_amount) AS month_total_amount_check,
    SUM(CASE
          WHEN (pg.customer_city <> pg.store_city) OR (pg.customer_country <> pg.store_country)
          THEN pg.payment_amount
          ELSE 0
        END) AS foreign_store_amount
  FROM payment_to_store_geo AS pg
  GROUP BY
    pg.customer_id,
    pg.month_start
),
foreign_store_stats AS (
  SELECT
    mgs.customer_id,
    mgs.month_start,
    (1.0 * mgs.foreign_store_payment_rows) / NULLIF(mgs.total_payment_rows, 0) AS foreign_store_payment_share,
    mgs.foreign_store_amount,
    mgs.month_total_amount_check
  FROM month_customer_geo_splits AS mgs
),
distinct_payment_stores AS (
  SELECT
    pg.customer_id,
    pg.month_start,
    COUNT(DISTINCT pg.payment_store_id) AS distinct_payment_stores_count
  FROM payment_to_store_geo AS pg
  GROUP BY
    pg.customer_id,
    pg.month_start
),
-- список категорий фильмов по "основной части расходов": берём категории по доле суммы оплат за месяц/клиента,
-- и оставляем топ-N категории (3) как "основную часть"
month_customer_category_totals AS (
  SELECT
    pg.customer_id,
    pg.month_start,
    fc.l02 AS category_id,
    SUM(pg.payment_amount) AS category_amount
  FROM payment_to_store_geo AS pg
  JOIN flc fc ON fc.l01 = pg.film_id
  GROUP BY
    pg.customer_id,
    pg.month_start,
    fc.l02
),
month_customer_category_ranked AS (
  SELECT
    mcct.*,
    RANK() OVER (
      PARTITION BY mcct.customer_id, mcct.month_start
      ORDER BY mcct.category_amount DESC
    ) AS category_rank,
    SUM(mcct.category_amount) OVER (
      PARTITION BY mcct.customer_id, mcct.month_start
    ) AS month_total_amount_for_categories
  FROM month_customer_category_totals AS mcct
),
month_customer_category_top AS (
  SELECT
    mccr.customer_id,
    mccr.month_start,
    GROUP_CONCAT(cat.g02, ', ') AS main_categories
  FROM month_customer_category_ranked AS mccr
  JOIN cat ON cat.g01 = mccr.category_id
  WHERE mccr.category_rank <= 3
  GROUP BY mccr.customer_id, mccr.month_start
)
SELECT
  ch.customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  strftime('%Y-%m', ch.month_start) AS month,
  ROUND(ch.month_total_amount, 2) AS total_payment_amount,
  ch.payment_count,
  ROUND(fss.foreign_store_payment_share, 4) AS foreign_store_payment_share,
  ROUND(ch.max_payment_amount, 2) AS largest_payment_amount,
  RANK() OVER (
    PARTITION BY ch.customer_id
    ORDER BY ch.month_total_amount DESC
  ) AS month_rank_within_customer,
  mct.main_categories AS main_categories
FROM customer_month_history AS ch
JOIN cus AS c ON c.h01 = ch.customer_id
JOIN foreign_store_stats AS fss
  ON fss.customer_id = ch.customer_id
 AND fss.month_start = ch.month_start
JOIN distinct_payment_stores AS dps
  ON dps.customer_id = ch.customer_id
 AND dps.month_start = ch.month_start
LEFT JOIN month_customer_category_top AS mct
  ON mct.customer_id = ch.customer_id
 AND mct.month_start = ch.month_start
WHERE
  ch.prev_months_avg_amount IS NOT NULL
  AND ch.payment_count >= 5
  AND ch.month_total_amount > 3.0 * ch.prev_months_avg_amount
  AND dps.distinct_payment_stores_count >= 2
  AND fss.foreign_store_payment_share > 0
ORDER BY
  ch.customer_id,
  ch.month_start;