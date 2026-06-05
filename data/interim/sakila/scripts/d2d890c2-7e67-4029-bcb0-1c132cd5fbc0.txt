WITH daily_customer_payments AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        DATE(pay.p06) AS payment_day,
        SUM(pay.p05) AS daily_amount,
        COUNT(*) AS transaction_count,
        COUNT(DISTINCT pay.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM pay
    JOIN cus ON cus.h01 = pay.p02
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN stf ON stf.o01 = pay.p03
    GROUP BY
        cus.h01,
        cus.h03,
        cus.h04,
        cnt.c01,
        cnt.c02,
        DATE(pay.p06)
),
daily_staff_shares AS (
    SELECT
        p02 AS customer_id,
        DATE(p06) AS payment_day,
        p03 AS staff_id,
        COUNT(*) AS staff_transactions
    FROM pay
    GROUP BY p02, DATE(p06), p03
),
max_staff_share AS (
    SELECT
        dss.customer_id,
        dss.payment_day,
        MAX(1.0 * dss.staff_transactions / dcp.transaction_count) AS max_staff_transaction_share
    FROM daily_staff_shares dss
    JOIN daily_customer_payments dcp
      ON dcp.customer_id = dss.customer_id
     AND dcp.payment_day = dss.payment_day
    GROUP BY dss.customer_id, dss.payment_day
),
daily_store_shares AS (
    SELECT
        pay.p02 AS customer_id,
        DATE(pay.p06) AS payment_day,
        stf.o07 AS store_id,
        COUNT(*) AS store_transactions
    FROM pay
    JOIN stf ON stf.o01 = pay.p03
    GROUP BY pay.p02, DATE(pay.p06), stf.o07
),
max_store_share AS (
    SELECT
        dss.customer_id,
        dss.payment_day,
        MAX(1.0 * dss.store_transactions / dcp.transaction_count) AS max_store_transaction_share
    FROM daily_store_shares dss
    JOIN daily_customer_payments dcp
      ON dcp.customer_id = dss.customer_id
     AND dcp.payment_day = dss.payment_day
    GROUP BY dss.customer_id, dss.payment_day
),
customer_history AS (
    SELECT
        dcp.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_customer_payments prev
            WHERE prev.customer_id = dcp.customer_id
              AND prev.payment_day >= DATE(dcp.payment_day, '-30 days')
              AND prev.payment_day < dcp.payment_day
        ) AS personal_avg_prev_30d,
        (
            SELECT COUNT(*)
            FROM daily_customer_payments prev
            WHERE prev.customer_id = dcp.customer_id
              AND prev.payment_day >= DATE(dcp.payment_day, '-30 days')
              AND prev.payment_day < dcp.payment_day
        ) AS personal_days_prev_30d,
        (
            SELECT COUNT(*)
            FROM daily_customer_payments prev
            WHERE prev.customer_id = dcp.customer_id
              AND prev.payment_day < dcp.payment_day
        ) AS total_payment_days_before
    FROM daily_customer_payments dcp
),
country_daily_level AS (
    SELECT
        ch.*,
        AVG(ch.daily_amount) OVER (
            PARTITION BY ch.country_id, ch.payment_day
        ) AS country_avg_same_day,
        CUME_DIST() OVER (
            PARTITION BY ch.country_id
            ORDER BY ch.daily_amount DESC
        ) AS country_amount_top_rank
    FROM customer_history ch
),
scored_days AS (
    SELECT
        cdl.customer_id,
        cdl.customer_name,
        cdl.country_name,
        cdl.payment_day,
        cdl.daily_amount,
        cdl.transaction_count,
        cdl.personal_avg_prev_30d,
        cdl.country_avg_same_day,
        cdl.personal_days_prev_30d,
        cdl.total_payment_days_before,
        cdl.staff_count,
        cdl.store_count,
        mss.max_staff_transaction_share,
        mst.max_store_transaction_share,
        cdl.country_amount_top_rank,
        cdl.daily_amount / NULLIF(cdl.personal_avg_prev_30d, 0) AS personal_spike_ratio,
        cdl.daily_amount / NULLIF(cdl.country_avg_same_day, 0) AS country_avg_ratio,
        (
            cdl.daily_amount / NULLIF(cdl.personal_avg_prev_30d, 0)
            + cdl.daily_amount / NULLIF(cdl.country_avg_same_day, 0)
            + cdl.transaction_count * 0.10
            + cdl.staff_count * 0.25
            + cdl.store_count * 0.50
            + (1.0 - COALESCE(mss.max_staff_transaction_share, 1.0))
            + (1.0 - COALESCE(mst.max_store_transaction_share, 1.0))
        ) AS suspicious_score
    FROM country_daily_level cdl
    LEFT JOIN max_staff_share mss
      ON mss.customer_id = cdl.customer_id
     AND mss.payment_day = cdl.payment_day
    LEFT JOIN max_store_share mst
      ON mst.customer_id = cdl.customer_id
     AND mst.payment_day = cdl.payment_day
)
SELECT
    customer_id,
    customer_name,
    country_name,
    payment_day,
    ROUND(daily_amount, 2) AS daily_amount,
    transaction_count,
    ROUND(personal_avg_prev_30d, 2) AS personal_avg_prev_30d,
    ROUND(personal_spike_ratio, 2) AS personal_spike_ratio,
    ROUND(country_avg_same_day, 2) AS country_avg_same_day,
    ROUND(country_avg_ratio, 2) AS country_avg_ratio,
    staff_count,
    store_count,
    ROUND(max_staff_transaction_share, 3) AS max_staff_transaction_share,
    ROUND(max_store_transaction_share, 3) AS max_store_transaction_share,
    ROUND(country_amount_top_rank, 4) AS country_amount_top_rank,
    ROUND(suspicious_score, 2) AS suspicious_score
FROM scored_days
WHERE personal_days_prev_30d >= 5
  AND total_payment_days_before >= 10
  AND personal_avg_prev_30d > 0
  AND daily_amount >= personal_avg_prev_30d * 3
  AND country_amount_top_rank <= 0.05
ORDER BY suspicious_score DESC, daily_amount DESC
LIMIT 50;