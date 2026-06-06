WITH payment_enriched AS (
  SELECT
    p.p02 AS customer_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_date,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    date(p.p06) AS payment_day,
    strftime('%Y-%m', p.p06) AS payment_month
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
),
customer_monthly AS (
  SELECT
    pe.customer_id,
    pe.payment_month,
    COUNT(*) AS payment_count,
    SUM(pe.payment_amount) AS monthly_amount
  FROM payment_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.payment_month
),
customer_monthly_history AS (
  SELECT
    cm.*,
    AVG(cm.payment_count) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.payment_month
      ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_payment_count,
    AVG(cm.monthly_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.payment_month
      ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_monthly_amount
  FROM customer_monthly AS cm
),
country_monthly AS (
  SELECT
    pe.customer_id,
    pe.payment_month,
    country.c01 AS country_id,
    country.c02 AS country_name,
    SUM(pe.payment_amount) AS monthly_amount,
    COUNT(*) AS payment_count
  FROM payment_enriched AS pe
  JOIN cus AS c
    ON c.h01 = pe.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS country
    ON country.c01 = city.d03
  GROUP BY
    pe.customer_id,
    pe.payment_month,
    country.c01,
    country.c02
),
country_stats AS (
  SELECT
    country_id,
    payment_month,
    AVG(monthly_amount) AS avg_country_monthly_amount
  FROM country_monthly
  GROUP BY
    country_id,
    payment_month
),
country_ranked AS (
  SELECT
    cm.*,
    cs.avg_country_monthly_amount,
    PERCENT_RANK() OVER (
      PARTITION BY cm.country_id, cm.payment_month
      ORDER BY cm.monthly_amount
    ) AS country_percentile
  FROM country_monthly AS cm
  JOIN country_stats AS cs
    ON cs.country_id = cm.country_id
   AND cs.payment_month = cm.payment_month
),
daily_distribution AS (
  SELECT
    pe.customer_id,
    pe.payment_month,
    date(pe.payment_date) AS payment_day,
    COUNT(*) AS day_payment_count,
    COUNT(DISTINCT pe.staff_id) AS day_distinct_staff_count,
    COUNT(DISTINCT pe.store_id) AS day_distinct_store_count
  FROM payment_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.payment_month,
    date(pe.payment_date)
),
daily_24h_series AS (
  SELECT
    d1.customer_id,
    d1.payment_month,
    d1.payment_day,
    EXISTS (
      SELECT 1
      FROM payment_enriched AS x
      WHERE x.customer_id = d1.customer_id
        AND x.payment_date >= datetime(d1.payment_day)
        AND x.payment_date < datetime(d1.payment_day, '+24 hours')
      GROUP BY x.customer_id
      HAVING COUNT(*) >= 3
         AND COUNT(DISTINCT x.staff_id) >= 3
    ) AS has_24h_series
  FROM daily_distribution AS d1
),
final AS (
  SELECT
    cr.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    country_name,
    cr.payment_month,
    cr.monthly_amount,
    cr.payment_count,
    (cr.monthly_amount - COALESCE(ch.avg_prev_monthly_amount, 0)) AS deviation_from_personal_amount,
    (cr.payment_count - COALESCE(ch.avg_prev_payment_count, 0)) AS deviation_from_personal_count,
    (cr.monthly_amount - cr.avg_country_monthly_amount) AS deviation_from_country_avg,
    cr.country_percentile,
    MAX(CASE WHEN ds.has_24h_series THEN 1 ELSE 0 END) AS has_24h_series
  FROM country_ranked AS cr
  JOIN cus AS c
    ON c.h01 = cr.customer_id
  LEFT JOIN customer_monthly_history AS ch
    ON ch.customer_id = cr.customer_id
   AND ch.payment_month = cr.payment_month
  LEFT JOIN daily_24h_series AS ds
    ON ds.customer_id = cr.customer_id
   AND ds.payment_month = cr.payment_month
  GROUP BY
    cr.customer_id,
    c.h03,
    c.h04,
    country_name,
    cr.payment_month,
    cr.monthly_amount,
    cr.payment_count,
    ch.avg_prev_monthly_amount,
    ch.avg_prev_payment_count,
    cr.avg_country_monthly_amount,
    cr.country_percentile
)
SELECT
  customer_id,
  customer_name,
  country_name,
  payment_month,
  ROUND(monthly_amount, 2) AS monthly_amount,
  payment_count,
  ROUND(deviation_from_personal_amount, 2) AS deviation_from_personal_amount,
  ROUND(deviation_from_personal_count, 2) AS deviation_from_personal_count,
  ROUND(deviation_from_country_avg, 2) AS deviation_from_country_avg
FROM final
WHERE (
    avg_prev_monthly_amount IS NOT NULL
    AND monthly_amount >= avg_prev_monthly_amount * 3
    AND payment_count >= COALESCE(avg_prev_payment_count, 0) * 3
  )
  AND (
    country_percentile >= 0.95
    OR has_24h_series = 1
  )
ORDER BY
  payment_month DESC,
  monthly_amount DESC,
  customer_id;