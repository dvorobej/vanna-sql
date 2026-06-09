WITH payments_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    -- customer geo
    cn.c01 AS customer_country_id,
    cn.c02 AS customer_country,
    ct.d02 AS customer_city,
    -- staff/store geo
    s.o04 AS staff_address_id,
    stc.c01 AS staff_country_id,
    stc.c02 AS staff_country,
    stct.d02 AS staff_city,
    -- film category mapping
    r.q03 AS inv_id,
    i.n02 AS film_id
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
  JOIN stf s ON s.o01 = p.p03
  JOIN adr sa ON sa.e01 = s.o04
  JOIN cty stct ON stct.d01 = sa.e05
  JOIN cnt stc ON stc.c01 = stct.d03
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
),
payment_with_other_store_flag AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    pb.payment_id,
    pb.payment_amount,
    pb.staff_id,
    pb.staff_city,
    pb.staff_country_id,
    CASE
      WHEN pb.staff_city IS NULL OR pb.customer_city IS NULL THEN 0
      WHEN pb.staff_city <> pb.customer_city THEN 1
      WHEN pb.staff_country_id IS NULL OR pb.customer_country_id IS NULL THEN 0
      WHEN pb.staff_country_id <> pb.customer_country_id THEN 1
      ELSE 0
    END AS is_other_store_geo
  FROM payments_base pb
),
monthly_customer_payments AS (
  SELECT
    customer_id,
    month_start,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS month_total_amount,
    COUNT(DISTINCT CASE WHEN staff_id IS NOT NULL THEN staff_id END) AS distinct_staff_count,
    SUM(payment_amount) AS total_amount,
    MAX(payment_amount) AS max_payment,
    AVG(payment_amount) AS avg_payment_amount,
    SUM(CASE WHEN is_other_store_geo = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS share_other_store_payment_count,
    SUM(CASE WHEN is_other_store_geo = 1 THEN payment_amount ELSE 0 END) * 1.0 / NULLIF(SUM(payment_amount), 0) AS share_other_store_payment_amount
  FROM payment_with_other_store_flag
  GROUP BY customer_id, month_start
),
monthly_with_prev_avg AS (
  SELECT
    mcp.*,
    AVG(month_total_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount
  FROM monthly_customer_payments mcp
),
qualified_months AS (
  SELECT
    customer_id,
    month_start,
    month_total_amount,
    payment_count,
    share_other_store_payment_count,
    max_payment,
    prev_months_avg_amount
  FROM monthly_with_prev_avg
  WHERE prev_months_avg_amount IS NOT NULL
    AND payment_count >= 5
    AND month_total_amount > 3.0 * prev_months_avg_amount
),
month_ranks_within_customer AS (
  SELECT
    q.customer_id,
    q.month_start,
    q.month_total_amount,
    q.payment_count,
    q.share_other_store_payment_count,
    q.max_payment,
    RANK() OVER (
      PARTITION BY q.customer_id
      ORDER BY q.month_total_amount DESC, q.month_start
    ) AS month_rank_within_customer
  FROM qualified_months q
),
payment_categories AS (
  -- Allocate each payment to categories of its film (can be multiple per payment)
  SELECT
    pb.customer_id,
    pb.month_start,
    ca.g01 AS category_id,
    ca.g02 AS category_name,
    pb.payment_id
  FROM payments_base pb
  JOIN ren r ON r.q01 = pb.payment_id -- ensures r.q01 exists if payment linked
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN flc fc ON fc.l01 = i.n02
  LEFT JOIN cat ca ON ca.g01 = fc.l02
),
category_amounts AS (
  -- Sum payment amounts per (customer, month, category)
  SELECT
    q.customer_id,
    q.month_start,
    pc.category_name,
    SUM(pwf.payment_amount) AS category_total_amount,
    COUNT(*) AS category_payment_count
  FROM qualified_months q
  JOIN payment_with_other_store_flag pwf
    ON pwf.customer_id = q.customer_id
   AND pwf.month_start = q.month_start
   AND pwf.payment_id = pwf.payment_id
  JOIN payments_base pb
    ON pb.payment_id = pwf.payment_id
  LEFT JOIN payment_categories pc
    ON pc.payment_id = pb.payment_id
  GROUP BY
    q.customer_id,
    q.month_start,
    pc.category_name
),
primary_categories AS (
  -- "список категорий фильмов, на которые пришлась основная часть расходов."
  -- Interpret as categories whose cumulative amount reaches >= 80% of month total (per customer-month).
  SELECT
    ca.customer_id,
    ca.month_start,
    GROUP_CONCAT(ca.category_name, ', ') AS categories_list
  FROM (
    SELECT
      catm.customer_id,
      catm.month_start,
      catm.category_name,
      catm.category_total_amount,
      catm.category_total_amount / NULLIF(SUM(catm.category_total_amount) OVER (PARTITION BY catm.customer_id, catm.month_start), 0) AS category_share,
      SUM(catm.category_total_amount) OVER (
        PARTITION BY catm.customer_id, catm.month_start
        ORDER BY catm.category_total_amount DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS cumulative_amount
    FROM category_amounts catm
  ) ca
  JOIN (
    SELECT
      customer_id,
      month_start,
      month_total_amount
    FROM qualified_months
  ) q
    ON q.customer_id = ca.customer_id
   AND q.month_start = ca.month_start
  WHERE ca.cumulative_amount <= q.month_total_amount * 0.8
     OR ca.cumulative_amount >= q.month_total_amount * 0.8
  GROUP BY ca.customer_id, ca.month_start
)
SELECT
  mrc.customer_id,
  qmonth.month_start AS month,
  ROUND(mrc.month_total_amount, 2) AS month_total_amount,
  mrc.payment_count,
  ROUND(mrc.share_other_store_payment_count, 4) AS share_other_store_payment_count,
  ROUND(mrc.max_payment, 2) AS max_payment,
  mrc.month_rank_within_customer,
  COALESCE(pc.categories_list, '') AS primary_categories
FROM month_ranks_within_customer mrc
JOIN qualified_months qmonth
  ON qmonth.customer_id = mrc.customer_id
 AND qmonth.month_start = mrc.month_start
LEFT JOIN primary_categories pc
  ON pc.customer_id = mrc.customer_id
 AND pc.month_start = mrc.month_start
ORDER BY
  mrc.month_start,
  mrc.customer_id;