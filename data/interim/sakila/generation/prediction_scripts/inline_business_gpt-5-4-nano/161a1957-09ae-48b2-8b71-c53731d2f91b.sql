WITH daily_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  LEFT JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
daily_with_personal_avg AS (
  SELECT
    dc.*,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    (
      SELECT AVG(CAST(dcp2.day_amount AS REAL))
      FROM daily_customer AS dcp2
      WHERE dcp2.customer_id = dc.customer_id
        AND dcp2.payment_date >= date(dc.payment_date, '-30 days')
        AND dcp2.payment_date < dc.payment_date
    ) AS personal_avg_30d
  FROM daily_customer AS dc
  JOIN customer_geo AS cg
    ON cg.customer_id = dc.customer_id
),
country_daily_values AS (
  SELECT
    dwp.country_id,
    dwp.payment_date,
    dwp.day_amount
  FROM daily_with_personal_avg AS dwp
),
country_day_percentiles AS (
  SELECT
    country_id,
    payment_date,
    day_amount,
    ROW_NUMBER() OVER (
      PARTITION BY country_id
      ORDER BY day_amount
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY country_id
    ) AS cnt
  FROM country_daily_values
),
country_p95_threshold AS (
  SELECT
    country_id,
    MAX(CASE
      WHEN rn = CAST((0.95 * cnt) AS INT) THEN day_amount
      ELSE NULL
    END) AS p95_amount
  FROM country_day_percentiles
  GROUP BY country_id
),
qualified_days AS (
  SELECT
    dwp.customer_id,
    dwp.country_id,
    dwp.country_name,
    dwp.city_name,
    dwp.payment_date,
    dwp.day_amount,
    dwp.payment_count,
    dwp.staff_count,
    dwp.store_count,
    dwp.personal_avg_30d,
    (dwp.day_amount - dwp.personal_avg_30d) AS deviation_from_personal_avg,
    cpt.p95_amount,
    RANK() OVER (
      PARTITION BY dwp.country_id
      ORDER BY (dwp.day_amount - dwp.personal_avg_30d) DESC
    ) AS suspicion_rank_in_country
  FROM daily_with_personal_avg AS dwp
  JOIN country_p95_threshold AS cpt
    ON cpt.country_id = dwp.country_id
  WHERE dwp.personal_avg_30d IS NOT NULL
    AND dwp.personal_avg_30d > 0
    AND dwp.payment_count >= 3
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
    AND dwp.day_amount > 2 * dwp.personal_avg_30d
    AND dwp.day_amount > cpt.p95_amount
),
staff_list AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    GROUP_CONCAT(DISTINCT st.o02 || ' ' || st.o03) AS staff_list
  FROM pay AS p
  JOIN stf AS st
    ON st.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
final AS (
  SELECT
    qd.customer_id,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    qd.payment_date,
    qd.payment_count,
    ROUND(qd.day_amount, 2) AS day_amount,
    qd.staff_count,
    qd.store_count,
    COALESCE(sl.staff_list, '') AS staff_list,
    ROUND(qd.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    qd.suspicion_rank_in_country
  FROM qualified_days AS qd
  JOIN customer_geo AS cg
    ON cg.customer_id = qd.customer_id
  LEFT JOIN staff_list AS sl
    ON sl.customer_id = qd.customer_id
   AND sl.payment_date = qd.payment_date
)
SELECT *
FROM final
ORDER BY
  country_name,
  suspicion_rank_in_country,
  day_amount DESC,
  customer_id,
  payment_date;