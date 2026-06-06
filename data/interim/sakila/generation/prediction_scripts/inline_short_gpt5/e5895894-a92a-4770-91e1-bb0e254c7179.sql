WITH payment_detail AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    stf.o02 || ' ' || stf.o03 AS staff_name,
    stf.o07 AS store_id,
    p.p04 AS rental_id,
    flm.i01 AS film_id,
    flm.i02 AS film_title
  FROM pay AS p
  JOIN stf AS stf
    ON stf.o01 = p.p03
  LEFT JOIN ren AS ren
    ON ren.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = ren.q03
  LEFT JOIN flm AS flm
    ON flm.i01 = inv.n02
),
customer_day AS (
  SELECT
    customer_id,
    payment_day,
    COUNT(payment_id) AS payment_count,
    SUM(payment_amount) AS daily_amount
  FROM payment_detail
  GROUP BY
    customer_id,
    payment_day
),
customer_day_scored AS (
  SELECT
    customer_day.*,
    AVG(daily_amount) OVER (
      PARTITION BY customer_id
    ) AS customer_avg_daily_amount,
    RANK() OVER (
      PARTITION BY customer_id
      ORDER BY daily_amount DESC
    ) AS customer_day_amount_rank
  FROM customer_day
),
staff_day_amount AS (
  SELECT
    customer_id,
    payment_day,
    staff_id,
    staff_name,
    store_id,
    SUM(payment_amount) AS staff_daily_amount
  FROM payment_detail
  GROUP BY
    customer_id,
    payment_day,
    staff_id,
    staff_name,
    store_id
),
dominant_staff AS (
  SELECT
    customer_id,
    payment_day,
    staff_id,
    staff_name,
    store_id,
    staff_daily_amount
  FROM (
    SELECT
      staff_day_amount.*,
      ROW_NUMBER() OVER (
        PARTITION BY customer_id, payment_day
        ORDER BY staff_daily_amount DESC, staff_id
      ) AS rn
    FROM staff_day_amount
  )
  WHERE rn = 1
),
day_films AS (
  SELECT
    customer_id,
    payment_day,
    COUNT(DISTINCT film_id) AS unique_rented_film_count,
    GROUP_CONCAT(DISTINCT film_title) AS unique_rented_films
  FROM payment_detail
  WHERE film_id IS NOT NULL
  GROUP BY
    customer_id,
    payment_day
),
category_counts AS (
  SELECT
    pd.customer_id,
    pd.payment_day,
    cat.g02 AS category_name,
    COUNT(*) AS category_payment_count
  FROM payment_detail AS pd
  JOIN flc AS flc
    ON flc.l01 = pd.film_id
  JOIN cat AS cat
    ON cat.g01 = flc.l02
  GROUP BY
    pd.customer_id,
    pd.payment_day,
    cat.g02
),
most_frequent_category AS (
  SELECT
    customer_id,
    payment_day,
    category_name
  FROM (
    SELECT
      category_counts.*,
      ROW_NUMBER() OVER (
        PARTITION BY customer_id, payment_day
        ORDER BY category_payment_count DESC, category_name
      ) AS rn
    FROM category_counts
  )
  WHERE rn = 1
)
SELECT
  cus.h01 AS customer_id,
  cus.h03 AS first_name,
  cus.h04 AS last_name,
  cus.h05 AS email,
  cty.d02 AS city,
  cnt.c02 AS country,
  cds.payment_day,
  ROUND(cds.daily_amount, 2) AS daily_amount,
  cds.payment_count,
  ROUND(cds.customer_avg_daily_amount, 2) AS customer_avg_daily_amount,
  ROUND(cds.daily_amount / NULLIF(cds.customer_avg_daily_amount, 0), 2) AS amount_to_avg_ratio,
  COALESCE(df.unique_rented_film_count, 0) AS unique_rented_film_count,
  COALESCE(df.unique_rented_films, '') AS unique_rented_films,
  ds.staff_id AS dominant_staff_id,
  ds.staff_name AS dominant_staff_name,
  ds.store_id AS dominant_store_id,
  ROUND(ds.staff_daily_amount, 2) AS dominant_staff_amount,
  ROUND(ds.staff_daily_amount / NULLIF(cds.daily_amount, 0), 4) AS dominant_staff_turnover_share,
  COALESCE(mfc.category_name, '') AS most_frequent_category,
  cds.customer_day_amount_rank
FROM customer_day_scored AS cds
JOIN dominant_staff AS ds
  ON ds.customer_id = cds.customer_id
 AND ds.payment_day = cds.payment_day
JOIN cus AS cus
  ON cus.h01 = cds.customer_id
JOIN adr AS adr
  ON adr.e01 = cus.h06
JOIN cty AS cty
  ON cty.d01 = adr.e05
JOIN cnt AS cnt
  ON cnt.c01 = cty.d03
LEFT JOIN day_films AS df
  ON df.customer_id = cds.customer_id
 AND df.payment_day = cds.payment_day
LEFT JOIN most_frequent_category AS mfc
  ON mfc.customer_id = cds.customer_id
 AND mfc.payment_day = cds.payment_day
WHERE cds.payment_count >= 3
  AND cds.customer_avg_daily_amount > 0
  AND cds.daily_amount > cds.customer_avg_daily_amount * 3
  AND ds.staff_daily_amount >= cds.daily_amount * 0.70
ORDER BY
  cds.daily_amount DESC,
  cds.customer_day_amount_rank,
  cus.h01,
  cds.payment_day;