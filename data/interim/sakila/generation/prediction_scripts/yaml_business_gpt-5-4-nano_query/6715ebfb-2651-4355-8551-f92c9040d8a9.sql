WITH RECURSIVE
months(month_start) AS (
  SELECT date('2004-01-01','start of month')
  UNION ALL
  SELECT date(month_start,'+1 month')
  FROM months
  WHERE month_start < date('2006-01-01','start of month')
),
payment_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06,'start of month') AS month_start,
    p.p01 AS payment_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p04 AS rental_id,
    s.o07 AS staff_store_id,
    c.h02 AS home_store_id,
    ct.c02 AS country_name,
    ci.d02 AS city_name,
    fcat.l02 AS film_category_id,
    fcat.l01 AS film_id
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt ct
    ON ct.c01 = ci.d03
  LEFT JOIN stf s
    ON s.o01 = p.p03
  LEFT JOIN ren r
    ON r.q01 = p.p04
  LEFT JOIN inv i
    ON i.n01 = r.q03
  LEFT JOIN flc fcat
    ON fcat.l01 = i.n02
),
monthly_customer AS (
  SELECT
    customer_id,
    month_start,
    MAX(country_name) AS country_name,
    MAX(city_name) AS city_name,
    MAX(home_store_id) AS store_id,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_total_amount,
    MAX(payment_amount) AS max_single_payment,
    SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM flc fc2
      JOIN cat ca2 ON ca2.g01 = fc2.l02
      WHERE fc2.l01 = (SELECT film_id FROM payment_base pb2 WHERE pb2.payment_id = payment_id LIMIT 1)
        AND ca2.g02 IN ('Action','New')
    ) THEN payment_amount ELSE 0 END) AS action_new_amount_estimate
  FROM payment_base
  GROUP BY customer_id, month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(month_total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_amount,
    AVG(payment_count * 1.0) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_month_payment_count
  FROM monthly_customer mc
),
country_month_stats AS (
  SELECT
    mwh.country_name,
    mwh.month_start,
    mwh.payment_count,
    -- медиана по клиентам страны за месяц через позицию (для чётного числа — усреднение двух центральных)
    AVG(mwh.payment_count) FILTER (
      WHERE mwh.payment_count IS NOT NULL
    ) AS dummy
  FROM monthly_with_history mwh
),
country_month_ordered AS (
  SELECT
    mwh.*,
    ROW_NUMBER() OVER (
      PARTITION BY mwh.country_name, mwh.month_start
      ORDER BY mwh.payment_count
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY mwh.country_name, mwh.month_start
    ) AS cnt
  FROM monthly_with_history mwh
),
country_month_median AS (
  SELECT
    country_name,
    month_start,
    AVG(payment_count * 1.0) AS median_payment_count
  FROM country_month_ordered
  WHERE rn IN (
    CAST((cnt + 1) / 2 AS INTEGER),
    CAST((cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY country_name, month_start
),
suspicious AS (
  SELECT
    mwh.*,
    cm.median_payment_count,
    (mwh.month_total_amount / NULLIF(mwh.personal_avg_month_amount,0)) AS ratio_to_personal_avg
  FROM monthly_with_history mwh
  JOIN country_month_median cm
    ON cm.country_name = mwh.country_name
   AND cm.month_start = mwh.month_start
  WHERE mwh.personal_avg_month_amount IS NOT NULL
    AND mwh.personal_avg_month_amount > 0
    AND mwh.month_total_amount > mwh.personal_avg_month_amount * 3
    AND mwh.payment_count > cm.median_payment_count
)
SELECT
  s.customer_id,
  s.country_name AS customer_country,
  s.city_name AS customer_city,
  s.store_id AS store_id,
  s.payment_count,
  ROUND(s.month_total_amount, 2) AS month_payment_sum,
  ROUND(s.max_single_payment, 2) AS max_single_payment,
  -- доля платежей по арендам категорий Action и New
  ROUND((
    SELECT
      CASE WHEN s.month_total_amount > 0 THEN
        SUM(pb.payment_amount) * 1.0 / s.month_total_amount
      ELSE 0
      END
    FROM pay pbpay
    WHERE pbpay.p02 = s.customer_id
      AND date(pbpay.p06,'start of month') = s.month_start
      AND pbpay.p04 IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM ren rr
        JOIN inv ii ON ii.n01 = rr.q03
        JOIN flc fcc ON fcc.l01 = ii.n02
        JOIN cat acc ON acc.g01 = fcc.l02
        WHERE rr.q01 = pbpay.p04
          AND acc.g02 IN ('Action','New')
      )
  ), 4) AS action_new_payments_share,
  RANK() OVER (
    PARTITION BY s.country_name, s.month_start
    ORDER BY s.month_total_amount DESC
  ) AS suspicious_customer_rank_in_country
FROM suspicious s
ORDER BY
  s.month_start,
  s.country_name,
  suspicious_customer_rank_in_country,
  s.customer_id;