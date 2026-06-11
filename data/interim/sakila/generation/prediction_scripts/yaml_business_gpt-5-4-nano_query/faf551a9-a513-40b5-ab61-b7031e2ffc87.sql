WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    ci.d02 AS city_name,
    c.h06 AS address_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
daily_base AS (
  SELECT
    p.p02 AS customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    date(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    MAX(CAST(p.p05 AS REAL)) AS max_single_payment,
    GROUP_CONCAT(DISTINCT st.o07) AS store_ids,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT st.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS st ON st.o01 = p.p03
  JOIN customer_geo AS cg ON cg.customer_id = p.p02
  GROUP BY
    p.p02,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    date(p.p06)
),
daily_with_personal_avg AS (
  SELECT
    db.*,
    (
      SELECT AVG(dbp.day_amount)
      FROM daily_base AS dbp
      WHERE dbp.customer_id = db.customer_id
        AND dbp.day_date >= date(db.day_date, '-30 day')
        AND dbp.day_date < db.day_date
    ) AS personal_avg_prev_30d
  FROM daily_base AS db
),
country_day_amounts AS (
  SELECT
    d.customer_id,
    d.country_name,
    d.day_date,
    d.day_amount
  FROM daily_with_personal_avg AS d
),
country_threshold AS (
  SELECT
    country_name,
    day_amount AS p95_day_amount
  FROM (
    SELECT
      cda.*,
      PERCENT_RANK() OVER (
        PARTITION BY cda.country_name
        ORDER BY cda.day_amount
      ) AS pr
    FROM country_day_amounts AS cda
  ) t
  WHERE pr >= 0.95
  ORDER BY p95_day_amount
  LIMIT 1
),
flagged AS (
  SELECT
    dwp.*,
    cth.p95_day_amount,
    (dwp.day_amount - dwp.personal_avg_prev_30d) AS deviation_from_personal_avg
  FROM daily_with_personal_avg AS dwp
  JOIN country_threshold AS cth
    ON cth.country_name = dwp.country_name
  WHERE dwp.personal_avg_prev_30d IS NOT NULL
    AND dwp.personal_avg_prev_30d > 0
    AND dwp.day_amount >= 3.0 * dwp.personal_avg_prev_30d
    AND dwp.day_amount > cth.p95_day_amount
),
ranked AS (
  SELECT
    f.*,
    RANK() OVER (
      PARTITION BY f.country_name
      ORDER BY f.day_amount DESC
    ) AS country_day_surge_rank
  FROM flagged AS f
)
SELECT
  day_date AS surge_date,
  first_name,
  last_name,
  country_name,
  city_name,
  store_ids AS store_id_list,
  payment_count,
  ROUND(day_amount, 2) AS day_amount,
  ROUND(personal_avg_prev_30d, 2) AS avg_prev_30d,
  ROUND(deviation_from_personal_avg, 2) AS deviation_from_avg,
  country_day_surge_rank
FROM ranked
ORDER BY
  country_name,
  country_day_surge_rank,
  surge_date,
  last_name,
  first_name;