WITH pay_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03,
    c.h04,
    date(p.p06) AS suspicious_day,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.j01 AS store_id,
    s.j01 AS j01,
    s.j01
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS st
    ON st.o01 = p.p03
  JOIN sto AS s
    ON s.j01 = st.o07
),
daily AS (
  SELECT
    pe.customer_id,
    pe.suspicious_day,
    COUNT(*) AS payment_count,
    SUM(pe.amount) AS day_amount,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pe.store_id) AS distinct_store_count
  FROM pay_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.suspicious_day
),
daily_with_avg AS (
  SELECT
    d.*,
    (
      SELECT AVG(d_prev.day_amount)
      FROM daily AS d_prev
      WHERE d_prev.customer_id = d.customer_id
        AND d_prev.suspicious_day >= date(d.suspicious_day, '-30 days')
        AND d_prev.suspicious_day < d.suspicious_day
    ) AS avg_prev_30d
  FROM daily AS d
),
suspicious_days AS (
  SELECT
    dwa.customer_id,
    dwa.suspicious_day,
    dwa.payment_count,
    dwa.day_amount,
    dwa.distinct_staff_count,
    dwa.distinct_store_count,
    dwa.avg_prev_30d,
    (dwa.day_amount / dwa.avg_prev_30d) AS exceed_ratio
  FROM daily_with_avg AS dwa
  WHERE dwa.avg_prev_30d IS NOT NULL
    AND dwa.avg_prev_30d > 0
    AND dwa.day_amount >= 3.0 * dwa.avg_prev_30d
    AND (dwa.distinct_staff_count >= 2 OR dwa.distinct_store_count >= 2)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03,
    c.h04,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
)
SELECT
  sd.customer_id,
  cg.h03 AS customer_first_name,
  cg.h04 AS customer_last_name,
  cg.country_name,
  cg.city_name,
  sd.suspicious_day,
  sd.day_amount,
  sd.payment_count,
  sd.distinct_staff_count,
  ROUND(sd.avg_prev_30d, 2) AS avg_prev_30d,
  RANK() OVER (
    ORDER BY sd.day_amount / sd.avg_prev_30d DESC, sd.day_amount DESC, sd.customer_id
  ) AS suspicious_exceed_rank
FROM suspicious_days AS sd
JOIN customer_geo AS cg
  ON cg.customer_id = sd.customer_id
ORDER BY
  suspicious_exceed_rank,
  sd.day_amount DESC,
  sd.customer_id,
  sd.suspicious_day;