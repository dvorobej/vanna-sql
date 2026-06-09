WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
daily_by_store AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    s.o07 AS store_id,
    s.o02 AS staff_first_name,
    s.o03 AS staff_last_name,
    cg.country_name,
    cg.city_name,
    cg.first_name,
    cg.last_name,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  JOIN customer_geo AS cg ON cg.customer_id = p.p02
  GROUP BY
    p.p02, date(p.p06), s.o07,
    s.o02, s.o03,
    cg.country_name, cg.city_name, cg.first_name, cg.last_name
),
daily_by_customer AS (
  SELECT
    customer_id,
    payment_date,
    country_name,
    city_name,
    first_name,
    last_name,
    COUNT(*) AS store_payment_rows,
    SUM(day_amount) AS day_amount,
    SUM(payment_count) AS payment_count,
    group_concat(DISTINCT store_id) AS store_list
  FROM daily_by_store
  GROUP BY
    customer_id, payment_date,
    country_name, city_name,
    first_name, last_name
),
with_personal_avg AS (
  SELECT
    d.*,
    (
      SELECT SUM(d2.day_amount) / 30.0
      FROM daily_by_customer AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 day')
        AND d2.payment_date < d.payment_date
    ) AS avg_daily_prev_30
  FROM daily_by_customer AS d
),
country_days_rank AS (
  SELECT
    dc.*,
    PERCENT_RANK() OVER (
      PARTITION BY dc.country_name
      ORDER BY dc.day_amount
    ) AS pr
  FROM daily_by_customer AS dc
),
qualified AS (
  SELECT
    wp.*,
    (wp.day_amount - wp.avg_daily_prev_30) AS deviation_from_avg,
    RANK() OVER (
      PARTITION BY wp.country_name
      ORDER BY (wp.day_amount - wp.avg_daily_prev_30) DESC,
               wp.day_amount DESC,
               wp.payment_date DESC,
               wp.customer_id
    ) AS burst_rank_in_country
  FROM with_personal_avg AS wp
  JOIN country_days_rank AS cdr
    ON cdr.customer_id = wp.customer_id
   AND cdr.payment_date = wp.payment_date
)
SELECT
  q.payment_date AS burst_date,
  q.first_name,
  q.last_name,
  q.country_name AS country,
  q.city_name AS city,
  q.store_list AS store_ids,
  q.payment_count,
  ROUND(q.day_amount, 2) AS day_amount,
  ROUND(q.avg_daily_prev_30, 2) AS avg_prev_30_days,
  ROUND(q.deviation_from_avg, 2) AS deviation_from_avg,
  q.burst_rank_in_country
FROM qualified AS q
WHERE q.avg_daily_prev_30 > 0
  AND q.day_amount >= 3.0 * q.avg_daily_prev_30
  AND (
    SELECT COUNT(*)
    FROM country_days_rank AS cd2
    WHERE cd2.country_name = q.country_name
      AND cd2.day_amount <= q.day_amount
  ) <= (
    SELECT COUNT(*) * 0.95
    FROM country_days_rank AS cd3
    WHERE cd3.country_name = q.country_name
  )
ORDER BY
  q.country_name,
  q.burst_rank_in_country,
  q.payment_date,
  q.customer_id;