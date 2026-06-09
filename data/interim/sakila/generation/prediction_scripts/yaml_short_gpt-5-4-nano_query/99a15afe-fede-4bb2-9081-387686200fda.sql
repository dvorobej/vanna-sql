SELECT *
  FROM monthly_store_country_ranks
  WHERE prev_months_count > 0
    AND personal_avg_prev IS NOT NULL
    AND personal_avg_prev > 0
    AND monthly_amount >= 3 * personal_avg_prev
    AND pct_rank_in_store_country_month <= 0.05
),
month_detail AS (
  SELECT
    b.customer_id,
    b.customer_first_name,
    b.customer_last_name,
    b.country,
    b.city,
    b.customer_store_id,
    b.issuing_store_id AS store_id,
    b.month_start,

    SUM(b.amount) AS monthly_amount,
    COUNT(*) AS payment_count,

    COUNT(DISTINCT b.staff_id) AS distinct_staff_count,

    SUM(
      CASE
        WHEN b.return_date IS NOT NULL
             AND julianday(b.return_date) - julianday(b.rental_date) >
                 (SELECT rental_duration FROM flm WHERE i01 = b.film_id)
        THEN 1
        ELSE 0
      END
    ) AS late_return_payment_count
  FROM base b
  WHERE EXISTS (
    SELECT 1
    FROM qualifying_months q
    WHERE q.customer_id = b.customer_id
      AND q.month_start = b.month_start
      AND q.customer_store_id = b.customer_store_id
      AND q.country = b.country
  )
  GROUP BY
    b.customer_id,
    b.customer_first_name,
    b.customer_last_name,
    b.country,
    b.city,
    b.customer_store_id,
    b.issuing_store_id,
    b.month_start
),
store_month_customer_rank AS (
  SELECT
    md.*,
    RANK() OVER (
      PARTITION BY md.store_id, md.month_start
      ORDER BY md.monthly_amount DESC
    ) AS customer_store_month_rank
  FROM month_detail md
)
SELECT
  md.customer_id,
  md.customer_first_name || ' ' || md.customer_last_name AS customer_name,
  md.country,
  md.city,
  md.store_id AS store_id,
  strftime('%Y-%m', md.month_start) AS payment_month,
  ROUND(md.monthly_amount, 2) AS monthly_amount,
  md.payment_count,
  md.distinct_staff_count,
  ROUND(
    1.0 * md.late_return_payment_count / NULLIF(md.payment_count, 0),
    4
  ) AS late_return_payment_share,
  smcr.customer_store_month_rank AS customer_month_store_amount_rank
FROM store_month_customer_rank smcr
ORDER BY
  smcr.payment_month,
  smcr.store_id,
  smcr.customer_store_month_rank,
  smcr.customer_id;