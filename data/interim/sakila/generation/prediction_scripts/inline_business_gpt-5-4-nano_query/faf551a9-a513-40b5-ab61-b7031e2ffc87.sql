WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    c.h06 AS address_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty ON cty.d01 = a.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    DATE(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    GROUP_CONCAT(DISTINCT CAST(s.o07 AS TEXT)) AS stores_id_list
  FROM pay AS p
  JOIN customer_geo AS cg ON cg.customer_id = p.p02
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02, cg.first_name, cg.last_name, cg.country_name, cg.city_name, DATE(p.p06)
),
with_personal_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dpp.day_amount)
      FROM daily_payments AS dpp
      WHERE dpp.customer_id = dp.customer_id
        AND dpp.payment_date >= DATE(dp.payment_date, '-30 days')
        AND dpp.payment_date < dp.payment_date
    ) AS avg_prev_30d
  FROM daily_payments AS dp
),
country_daily_rank AS (
  SELECT
    wpa.*,
    PERCENT_RANK() OVER (
      PARTITION BY country_name
      ORDER BY day_amount
    ) AS pr
  FROM with_personal_avg AS wpa
),
country_p95 AS (
  /* approx p95 via NTILE(20): "верхние 5%" => tile 20 */
  SELECT
    country_name,
    payment_date,
    day_amount,
    customer_id,
    first_name,
    last_name,
    city_name,
    avg_prev_30d,
    pr,
    staff_count,
    store_count,
    payment_count,
    stores_id_list,
    DENSE_RANK() OVER (
      PARTITION BY country_name
      ORDER BY day_amount DESC
    ) AS country_day_splash_rank
  FROM country_daily_rank
  WHERE avg_prev_30d IS NOT NULL
),
suspicious AS (
  SELECT *
  FROM country_p95
  WHERE
    day_amount >= 3 * avg_prev_30d
    AND pr >= 0.95
),
final AS (
  SELECT
    s.payment_date,
    s.first_name,
    s.last_name,
    s.country_name,
    s.city_name,
    s.stores_id_list AS store_list,
    s.payment_count,
    ROUND(s.day_amount, 2) AS day_amount,
    ROUND(s.avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(s.day_amount - s.avg_prev_30d, 2) AS deviation_from_avg,
    DENSE_RANK() OVER (
      PARTITION BY s.country_name
      ORDER BY (s.day_amount / NULLIF(s.avg_prev_30d, 0)) DESC,
               s.day_amount DESC,
               s.customer_id
    ) AS customer_splash_rank_in_country
  FROM suspicious AS s
)
SELECT
  payment_date,
  first_name,
  last_name,
  country_name,
  city_name,
  store_list,
  payment_count,
  day_amount,
  avg_prev_30d,
  deviation_from_avg,
  customer_splash_rank_in_country
FROM final
ORDER BY
  country_name,
  customer_splash_rank_in_country,
  payment_date;