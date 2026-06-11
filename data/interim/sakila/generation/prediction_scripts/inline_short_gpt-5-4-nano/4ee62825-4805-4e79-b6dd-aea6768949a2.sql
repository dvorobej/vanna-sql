WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    s.o02 || ' ' || s.o03 AS staff_name,
    COALESCE(r.q01, p.p04) AS rent_id,
    p.p05 AS amount,
    p.p06 AS payment_ts,
    DATE(p.p06) AS payment_date,
    cu.h01 AS cu_id,
    cu.h03 AS first_name,
    cu.h04 AS last_name,
    ci.d02 AS city_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    st.o01 AS store_id
  FROM pay AS p
  JOIN cus AS cu
    ON cu.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = cu.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ci.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN sto AS st
    ON st.j01 = s.o07
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  WHERE cu.h07 = 'Y'
),
daily_rollup AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    city_name,
    country_id,
    country_name,
    payment_date,
    SUM(amount) AS day_total_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT staff_id) AS staff_count,
    COUNT(DISTINCT store_id) AS store_count,
    group_concat(DISTINCT staff_name) AS staff_list,
    MIN(payment_ts) AS first_operation_ts,
    MAX(payment_ts) AS last_operation_ts,
    MAX(amount) AS max_payment_amount,
    COUNT(DISTINCT store_id) AS distinct_store_count
  FROM payment_base
  GROUP BY
    customer_id, first_name, last_name,
    city_name, country_id, country_name, payment_date
),
customer_history_avg AS (
  SELECT
    d.customer_id,
    AVG(d.day_total_amount) AS customer_avg_amount_hist
  FROM daily_rollup AS d
  GROUP BY d.customer_id
),
country_95p AS (
  SELECT
    dr.country_id,
    dr.payment_date,
    dr.day_total_amount,
    c95.cnt,
    c95.rn_target
  FROM (
    SELECT
      country_id,
      payment_date,
      day_total_amount,
      ROW_NUMBER() OVER (PARTITION BY country_id ORDER BY day_total_amount) AS rn,
      COUNT(*) OVER (PARTITION BY country_id) AS cnt
    FROM daily_rollup
  ) AS dr
  JOIN (
    SELECT
      country_id,
      MAX(cnt) AS cnt,
      CAST(CEIL(0.95 * MAX(cnt)) AS INT) AS rn_target
    FROM (
      SELECT
        country_id,
        COUNT(*) OVER (PARTITION BY country_id) AS cnt
      FROM daily_rollup
      GROUP BY country_id
    )
    GROUP BY country_id
  ) AS c95
    ON c95.country_id = dr.country_id
  WHERE dr.rn = c95.rn_target
),
scored AS (
  SELECT
    d.*,
    cha.customer_avg_amount_hist,
    cp95.day_total_amount AS country_p95_amount,
    d.day_total_amount - cha.customer_avg_amount_hist AS deviation_from_customer_avg,
    ROW_NUMBER() OVER (
      PARTITION BY d.country_id
      ORDER BY d.day_total_amount DESC, d.payment_date DESC, d.customer_id
    ) AS suspicion_rank
  FROM daily_rollup AS d
  JOIN customer_history_avg AS cha
    ON cha.customer_id = d.customer_id
  JOIN country_95p AS cp95
    ON cp95.country_id = d.country_id
  WHERE d.payment_count >= 3
    AND d.staff_count >= 2
    AND d.store_count >= 1
    AND d.day_total_amount > cha.customer_avg_amount_hist
    AND d.day_total_amount >= cp95.day_total_amount
)
SELECT
  customer_id,
  first_name,
  last_name,
  city_name,
  country_name,
  payment_date,
  ROUND(day_total_amount, 2) AS day_total_amount,
  payment_count,
  staff_count,
  distinct_store_count AS store_count,
  staff_list,
  first_operation_ts,
  last_operation_ts,
  ROUND(max_payment_amount, 2) AS max_payment_amount,
  suspicion_rank AS suspicion_rank_in_country
FROM scored
ORDER BY
  country_name,
  suspicion_rank,
  payment_date,
  customer_id;