SELECT AVG(prev_month_total_amount)
      FROM monthly mm2
      WHERE mm2.customer_id = m.customer_id
        AND mm2.month_start < m.month_start
        AND mm2.month_total_amount IS NOT NULL
    )
    AND distinct_payment_stores >= 2
    AND foreign_store_payment_count > 0
),
top_categories AS (
  SELECT
    c.customer_id,
    c.month_start,
    fc.category_name,
    SUM(c.payment_amount) AS category_amount,
    DENSE_RANK() OVER (
      PARTITION BY c.customer_id, c.month_start
      ORDER BY SUM(c.payment_amount) DESC
    ) AS category_rank
  FROM cpay_geo c
  JOIN film_categories fc ON fc.film_id = c.film_id
  GROUP BY
    c.customer_id, c.month_start, fc.category_name
),
main_category_list AS (
  SELECT
    customer_id,
    month_start,
    GROUP_CONCAT(category_name, ', ') AS main_categories
  FROM top_categories
  WHERE category_rank <= 3
  GROUP BY customer_id, month_start
)
SELECT
  mo.customer_id,
  mo.month_start AS month,
  ROUND(mo.month_total_amount, 2) AS month_total_amount,
  mo.payment_count,
  ROUND(mo.foreign_store_payment_share, 4) AS foreign_store_payment_share,
  ROUND(mo.max_payment, 2) AS max_payment,
  mo.customer_month_amount_rank_in_customer AS customer_month_rank_in_customer,
  mcl.main_categories AS main_categories
FROM monthly_ok mo
LEFT JOIN main_category_list mcl
  ON mcl.customer_id = mo.customer_id
 AND mcl.month_start = mo.month_start
ORDER BY
  mo.month_start,
  mo.customer_id;