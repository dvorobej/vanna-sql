WITH daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
qualified_days AS (
  SELECT
    d.customer_id,
    d.payment_date,
    d.day_amount,
    d.payment_count,
    d.staff_count,
    d.store_count
  FROM daily AS d
  WHERE d.payment_count >= 3
    AND (d.staff_count >= 2 OR d.store_count >= 2)
),
customer_geo_daily AS (
  SELECT
    q.customer_id,
    q.payment_date,
    q.day_amount,
    q.payment_count,
    q.staff_count,
    q.store_count,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    cnt.c01 AS country_id
  FROM qualified_days AS q
  JOIN cus AS c
    ON c.h01 = q.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
with_history AS (
  SELECT
    cg.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily AS d2
      WHERE d2.customer_id = cg.customer_id
        AND d2.payment_date >= date(cg.payment_date, '-30 days')
        AND d2.payment_date < cg.payment_date
    ) AS avg_prev_30d_amount
  FROM customer_geo_daily AS cg
),
joined_pay_staff AS (
  SELECT
    wh.customer_id,
    wh.payment_date,
    GROUP_CONCAT(DISTINCT (st.o02 || ' ' || st.o03)) AS staff_list,
    COUNT(DISTINCT st.o01) AS distinct_staff_count_detailed
  FROM with_history AS wh
  JOIN pay AS p
    ON p.p02 = wh.customer_id
   AND date(p.p06) = wh.payment_date
  JOIN stf AS st
    ON st.o01 = p.p03
  GROUP BY
    wh.customer_id,
    wh.payment_date
),
country_p95 AS (
  SELECT
    wh.country_id,
    wh.payment_date,
    wh.day_amount,
    wh.avg_prev_30d_amount,
    wh.day_amount / NULLIF(wh.avg_prev_30d_amount, 0) AS day_vs_avg_ratio,
    PERCENT_RANK() OVER (PARTITION BY wh.country_id ORDER BY wh.day_amount) AS pr
  FROM with_history AS wh
),
ranked_by_ratio AS (
  SELECT
    wh.*,
    CASE
      WHEN wh.avg_prev_30d_amount IS NULL THEN NULL
      ELSE wh.day_amount - wh.avg_prev_30d_amount
    END AS deviation_from_personal_avg
  FROM with_history AS wh
),
country_95rank AS (
  SELECT
    rbr.*,
    RANK() OVER (
      PARTITION BY rbr.country_id
      ORDER BY rbr.day_amount DESC
    ) AS day_amount_rank_in_country,
    COUNT(*) OVER (PARTITION BY rbr.country_id) AS country_day_count
  FROM ranked_by_ratio AS rbr
)
SELECT
  c95.customer_id AS h01,
  c95.first_name || ' ' || c95.last_name AS customer_name,
  c95.country_name AS c02,
  c95.city_name AS d02,
  c95.payment_date AS p06_day,
  c95.payment_count AS payment_count,
  ROUND(c95.day_amount, 2) AS day_amount,
  jps.staff_list AS staff_list,
  c95.avg_prev_30d_amount AS avg_prev_30d_amount,
  ROUND(c95.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  c95.day_amount_rank_in_country AS suspicion_rank_in_country_95
FROM country_95rank AS c95
LEFT JOIN joined_pay_staff AS jps
  ON jps.customer_id = c95.customer_id
 AND jps.payment_date = c95.payment_date
WHERE c95.avg_prev_30d_amount IS NOT NULL
ORDER BY
  c95.country_name,
  suspicion_rank_in_country_95,
  c95.day_amount DESC,
  c95.customer_id,
  c95.payment_date;