SELECT
  t.customer_id,
  t.customer_first_name,
  t.customer_last_name,
  t.customer_country,
  t.customer_city,
  t.customer_store AS home_store_id,
  t.payment_month,
  ROUND(t.month_total_amount, 2) AS month_total_amount,
  t.month_payment_count,
  t.distinct_staff_count,
  ROUND(t.return_late_payment_share, 4) AS return_late_payment_share,
  t.shop_month_client_rank
FROM (
  WITH
  payments AS (
    SELECT
      p.p01 AS payment_id,
      p.p02 AS customer_id,
      c.h03 AS customer_first_name,
      c.h04 AS customer_last_name,
      c.h02 AS customer_store,
      caddr.e05 AS customer_city_id,
      ci.d02 AS customer_city,
      co.c02 AS customer_country,
      date(p.p06, 'start of month') AS payment_month,
      CAST(p.p05 AS REAL) AS payment_amount,
      p.p03 AS staff_id,
      p.p04 AS rental_id,
      r.q05 AS rental_return_date,
      /* planned return date = rental_date + rental_duration days (flm.i07) */
      date(r.q02, '+' || flm.i07 || ' days') AS planned_return_date,
      flm.i01 AS film_id
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr caddr ON caddr.e01 = c.h06
    JOIN cty ci ON ci.d01 = caddr.e05
    JOIN cnt co ON co.c01 = ci.d03
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flm ON flm.i01 = i.n02
  ),
  monthly AS (
    SELECT
      customer_id,
      customer_first_name,
      customer_last_name,
      customer_country,
      customer_city,
      customer_store,
      payment_month,
      COUNT(*) AS month_payment_count,
      SUM(payment_amount) AS month_total_amount,
      COUNT(DISTINCT staff_id) AS distinct_staff_count,
      SUM(
        CASE
          WHEN rental_id IS NOT NULL
           AND rental_return_date IS NOT NULL
           AND rental_return_date > planned_return_date
          THEN 1
          ELSE 0
        END
      ) AS late_return_payment_count
    FROM payments
    GROUP BY
      customer_id,
      customer_first_name,
      customer_last_name,
      customer_country,
      customer_city,
      customer_store,
      payment_month
  ),
  with_prev_avg AS (
    SELECT
      m.*,
      AVG(month_total_amount) OVER (
        PARTITION BY customer_id
        ORDER BY payment_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ) AS personal_avg_prev_months
    FROM monthly m
  ),
  shop_country_rank AS (
    /* 95th percentile by shop(customer_store) and country for each month among customers */
    SELECT
      w.customer_id,
      w.payment_month,
      w.customer_store,
      w.customer_country,
      w.month_total_amount,
      w.month_payment_count,
      w.customer_first_name,
      w.customer_last_name,
      w.customer_city,
      w.distinct_staff_count,
      w.late_return_payment_count,
      w.personal_avg_prev_months,
      PERCENT_RANK() OVER (
        PARTITION BY w.customer_store, w.customer_country, w.payment_month
        ORDER BY w.month_total_amount DESC
      ) AS pct_rank_desc
    FROM with_prev_avg w
  ),
  monthly_with_home_rank AS (
    SELECT
      scr.*,
      RANK() OVER (
        PARTITION BY scr.customer_store, scr.payment_month
        ORDER BY scr.month_total_amount DESC
      ) AS shop_month_client_rank
    FROM shop_country_rank scr
  )
  SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    customer_country,
    customer_city,
    customer_store,
    payment_month,
    month_total_amount,
    month_payment_count,
    distinct_staff_count,
    CASE
      WHEN month_payment_count = 0 THEN 0
      ELSE 1.0 * late_return_payment_count / month_payment_count
    END AS return_late_payment_share,
    shop_month_client_rank,
    personal_avg_prev_months
  FROM monthly_with_home_rank
  WHERE
    personal_avg_prev_months IS NOT NULL
    AND personal_avg_prev_months > 0
    AND month_total_amount >= 3.0 * personal_avg_prev_months
    AND pct_rank_desc <= 0.05
) AS t
ORDER BY
  t.customer_country,
  t.customer_store,
  t.payment_month,
  t.shop_month_client_rank,
  t.customer_id;