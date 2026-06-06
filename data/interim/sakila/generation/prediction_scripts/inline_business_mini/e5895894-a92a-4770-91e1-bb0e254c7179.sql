WITH payment_detail AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h05 AS email,
    cnt.c02 AS country_name,
    ct.d02 AS city_name,
    DATE(p.p06) AS payment_day,
    p.p01 AS payment_id,
    p.p03 AS staff_id,
    stf.o07 AS store_id,
    CAST(p.p05 AS REAL) AS amount,
    inv.n02 AS film_id,
    flm.i02 AS film_title,
    cat.g02 AS category_name
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
  JOIN stf AS stf
    ON stf.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = r.q03
  LEFT JOIN flm AS flm
    ON flm.i01 = inv.n02
  LEFT JOIN fla AS fa
    ON fa.k02 = flm.i01
  LEFT JOIN cat AS cat
    ON cat.g01 = fa.k01
),
daily AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    email,
    country_name,
    city_name,
    payment_day,
    COUNT(*) AS payment_count,
    SUM(amount) AS daily_sum,
    COUNT(DISTINCT film_id) AS unique_rented_films,
    COUNT(DISTINCT staff_id) AS unique_staff_count
  FROM payment_detail
  GROUP BY
    customer_id, first_name, last_name, email, country_name, city_name, payment_day
),
daily_with_avg AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.daily_sum)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_day < d.payment_day
    ) AS avg_daily_sum
  FROM daily AS d
),
staff_dominance AS (
  SELECT
    pd.customer_id,
    pd.payment_day,
    pd.staff_id,
    SUM(pd.amount) AS staff_sum,
    SUM(pd.amount) * 1.0 / d.daily_sum AS staff_share,
    ROW_NUMBER() OVER (
      PARTITION BY pd.customer_id, pd.payment_day
      ORDER BY SUM(pd.amount) DESC, pd.staff_id
    ) AS rn_staff
  FROM payment_detail AS pd
  JOIN daily AS d
    ON d.customer_id = pd.customer_id
   AND d.payment_day = pd.payment_day
  GROUP BY pd.customer_id, pd.payment_day, pd.staff_id
),
dominant_staff AS (
  SELECT
    customer_id,
    payment_day,
    staff_id AS dominant_staff_id,
    store_id AS dominant_store_id,
    staff_sum,
    staff_share
  FROM (
    SELECT
      pd.customer_id,
      pd.payment_day,
      pd.staff_id,
      pd.store_id,
      SUM(pd.amount) AS staff_sum,
      SUM(pd.amount) * 1.0 / d.daily_sum AS staff_share,
      ROW_NUMBER() OVER (
        PARTITION BY pd.customer_id, pd.payment_day
        ORDER BY SUM(pd.amount) DESC, pd.staff_id
      ) AS rn
    FROM payment_detail AS pd
    JOIN daily AS d
      ON d.customer_id = pd.customer_id
     AND d.payment_day = pd.payment_day
    GROUP BY pd.customer_id, pd.payment_day, pd.staff_id, pd.store_id
  )
  WHERE rn = 1
),
category_counts AS (
  SELECT
    pd.customer_id,
    pd.payment_day,
    pd.category_name,
    COUNT(*) AS category_payment_count,
    SUM(pd.amount) AS category_sum
  FROM payment_detail AS pd
  WHERE pd.category_name IS NOT NULL
  GROUP BY pd.customer_id, pd.payment_day, pd.category_name
),
top_category AS (
  SELECT
    customer_id,
    payment_day,
    category_name AS dominant_category
  FROM (
    SELECT
      customer_id,
      payment_day,
      category_name,
      category_payment_count,
      category_sum,
      ROW_NUMBER() OVER (
        PARTITION BY customer_id, payment_day
        ORDER BY category_payment_count DESC, category_sum DESC, category_name
      ) AS rn
    FROM category_counts
  )
  WHERE rn = 1
),
ranked AS (
  SELECT
    d.*,
    COALESCE(da.avg_daily_sum, 0) AS avg_daily_sum_prev,
    RANK() OVER (
      PARTITION BY d.customer_id
      ORDER BY d.daily_sum DESC, d.payment_day
    ) AS day_sum_rank
  FROM daily_with_avg AS d
  LEFT JOIN daily_with_avg AS da
    ON da.customer_id = d.customer_id
   AND da.payment_day = d.payment_day
)
SELECT
  r.customer_id,
  r.first_name,
  r.last_name,
  r.email,
  r.city_name,
  r.country_name,
  r.payment_day,
  r.payment_count,
  ROUND(r.daily_sum, 2) AS daily_sum,
  ROUND(r.avg_daily_sum, 2) AS avg_daily_sum,
  r.unique_rented_films,
  ds.dominant_staff_id,
  ds.dominant_store_id,
  ROUND(ds.staff_share, 4) AS dominant_staff_share,
  tc.dominant_category,
  r.day_sum_rank
FROM ranked AS r
JOIN dominant_staff AS ds
  ON ds.customer_id = r.customer_id
 AND ds.payment_day = r.payment_day
LEFT JOIN top_category AS tc
  ON tc.customer_id = r.customer_id
 AND tc.payment_day = r.payment_day
WHERE r.payment_count >= 3
  AND r.avg_daily_sum > 0
  AND r.daily_sum > 3.0 * r.avg_daily_sum
  AND ds.staff_share >= 0.70
ORDER BY
  r.customer_id,
  r.day_sum_rank,
  r.payment_day;