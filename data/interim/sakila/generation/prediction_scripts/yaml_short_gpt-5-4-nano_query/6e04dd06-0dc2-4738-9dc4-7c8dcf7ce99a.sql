WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_id,
    SUM(CAST(p.p05 AS REAL)) AS month_sum,
    COUNT(*) AS month_payments,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
customer_history AS (
  SELECT
    m.*,
    (
      SELECT AVG(m2.month_sum)
      FROM monthly AS m2
      WHERE m2.customer_id = m.customer_id
        AND m2.month_id < m.month_id
        AND m2.month_id >= strftime('%Y-%m', date(m.month_id || '-01', '-3 months'))
    ) AS avg_prev3_month_sum
  FROM monthly AS m
),
country_month_ranked AS (
  SELECT
    ch.*,
    PERCENT_RANK() OVER (
      PARTITION BY ch.month_id, 
                   (SELECT c.h06 FROM cus c WHERE c.h01 = ch.customer_id)
      ORDER BY ch.month_sum
    ) AS pct_rank_by_country
  FROM customer_history AS ch
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  cn.c02 AS customer_country,
  cm.month_id AS month,
  ROUND(cm.month_sum, 2) AS month_sum,
  cm.month_payments,
  cm.staff_count,
  cm.store_count,
  ROUND(cm.avg_prev3_month_sum, 2) AS avg_prev3_month_sum,
  ROUND(CAST(cm.month_sum AS REAL) / NULLIF(cm.avg_prev3_month_sum, 0), 2) AS ratio_to_own_avg_prev3,
  cnm.country_month_median,
  ROUND(CAST(cm.month_sum AS REAL) / NULLIF(cnm.country_month_median, 0), 2) AS ratio_to_country_median,
  cm.rank_within_country
FROM (
  SELECT
    ch.*,
    cnt_rank.rank_within_country
  FROM (
    SELECT
      m.*,
      cu_country.c02 AS country_name_for_rank
    FROM monthly AS m
    JOIN cus cu
      ON cu.h01 = m.customer_id
    JOIN adr a
      ON a.e01 = cu.h06
    JOIN cty ci
      ON ci.d01 = a.e05
    JOIN cnt cu_country
      ON cu_country.c01 = ci.d03
  ) AS ch
  JOIN (
    SELECT
      m2.month_id,
      cu2.h01 AS customer_id,
      DENSE_RANK() OVER (
        PARTITION BY m2.month_id, cu_country2.c01
        ORDER BY m2.month_sum DESC
      ) AS rank_within_country
    FROM monthly AS m2
    JOIN cus cu2 ON cu2.h01 = m2.customer_id
    JOIN adr a2 ON a2.e01 = cu2.h06
    JOIN cty ci2 ON ci2.d01 = a2.e05
    JOIN cnt cu_country2 ON cu_country2.c01 = ci2.d03
  ) AS cnt_rank
    ON cnt_rank.month_id = ch.month_id
   AND cnt_rank.customer_id = ch.customer_id
) AS cm
JOIN cus c
  ON c.h01 = cm.customer_id
JOIN adr a
  ON a.e01 = c.h06
JOIN cty ci
  ON ci.d01 = a.e05
JOIN cnt cn
  ON cn.c01 = ci.d03
JOIN (
  SELECT
    country_id,
    month_id,
    AVG(month_sum) AS country_month_median
  FROM (
    SELECT
      ci3.d03 AS country_id,
      m3.month_id,
      m3.month_sum,
      ROW_NUMBER() OVER (
        PARTITION BY ci3.d03, m3.month_id
        ORDER BY m3.month_sum
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY ci3.d03, m3.month_id
      ) AS cnt
    FROM monthly m3
    JOIN cus c3 ON c3.h01 = m3.customer_id
    JOIN adr a3 ON a3.e01 = c3.h06
    JOIN cty ci3 ON ci3.d01 = a3.e05
  ) t
  WHERE rn IN (CAST((cnt + 1) / 2 AS INTEGER), CAST((cnt + 2) / 2 AS INTEGER))
  GROUP BY country_id, month_id
) AS cnm
  ON cnm.country_id = ci.d03
 AND cnm.month_id = cm.month_id
WHERE
  cm.avg_prev3_month_sum IS NOT NULL
  AND cm.avg_prev3_month_sum > 0
  AND cm.month_sum >= 3.0 * cm.avg_prev3_month_sum
  AND cnm.country_month_median > 0
  AND cm.month_sum >= 2.0 * cnm.country_month_median
  AND cm.rank_within_country <= CAST( ( (
        SELECT COUNT(*) 
        FROM monthly m4
        JOIN cus c4 ON c4.h01 = m4.customer_id
        JOIN adr a4 ON a4.e01 = c4.h06
        JOIN cty ci4 ON ci4.d01 = a4.e05
        WHERE m4.month_id = cm.month_id
          AND ci4.d03 = ci.d03
      ) * 0.05) + 0.9999 ) AS INTEGER
ORDER BY
  cn.c02,
  cm.month_id,
  cm.month_sum DESC,
  cm.customer_id;