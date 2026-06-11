WITH monthly_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        p.p06 AS payment_ts,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS month_amount,
        COUNT(p.p01) AS month_payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE
              WHEN r.q05 IS NOT NULL
                   AND (julianday(r.q05) - julianday(r.q02)) > f.i07
              THEN 1
              ELSE 0
            END) AS late_return_payment_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN sto AS s
        ON s.j01 = i.n03
    JOIN flm AS f
        ON f.i01 = i.n02
    JOIN (
        SELECT
            s2.j01 AS store_id,
            cn2.c01 AS country_id
        FROM sto AS s2
        JOIN adr AS a2
            ON a2.e01 = s2.j03
        JOIN cty AS ct2
            ON ct2.d01 = a2.e05
        JOIN cnt AS cn2
            ON cn2.c01 = ct2.d03
    ) AS store_country
        ON store_country.store_id = s.j01
    GROUP BY
        p.p02,
        c.h03,
        c.h04,
        date(p.p06, 'start of month')
),
monthly_with_personal_history AS (
    SELECT
        mcp.*,
        AVG(mcp.month_amount) OVER (
            PARTITION BY mcp.customer_id
            ORDER BY mcp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_avg_prev_month_amount
    FROM monthly_customer_payments AS mcp
),
country_store_month_stats AS (
    SELECT
        cn.c01 AS store_country_id,
        mcp.month_start,
        PERCENTILE_CONT_95 AS dummy
    FROM (
        SELECT 1
    ) x
)
SELECT
    mcp.customer_id,
    mcp.customer_name,
    cn.c02 AS country,
    ct.d02 AS city,
    s.j01 AS store_id,
    strftime('%Y-%m', mcp.month_start) AS payment_month,
    ROUND(mcp.month_amount, 2) AS month_amount,
    mcp.month_payment_count AS month_payment_count,
    mcp.distinct_staff_count,
    ROUND(1.0 * mcp.late_return_payment_count / NULLIF(mcp.month_payment_count, 0), 4) AS late_return_payment_share,
    RANK() OVER (
        PARTITION BY s.j01, cn.c01, mcp.month_start
        ORDER BY mcp.month_amount DESC
    ) AS customer_store_rank
FROM monthly_with_personal_history AS mcp
JOIN cus AS c
    ON c.h01 = mcp.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty AS ct
    ON ct.d01 = a.e05
JOIN cnt AS cn
    ON cn.c01 = ct.d03
JOIN ren AS r
    ON r.q01 = (
        SELECT p2.p04
        FROM pay AS p2
        WHERE p2.p02 = mcp.customer_id
          AND date(p2.p06, 'start of month') = mcp.month_start
        LIMIT 1
    )
JOIN inv AS i
    ON i.n01 = r.q03
JOIN sto AS s
    ON s.j01 = i.n03
WHERE mcp.personal_avg_prev_month_amount IS NOT NULL
  AND mcp.month_amount >= 3.0 * mcp.personal_avg_prev_month_amount
ORDER BY
    mcp.month_start,
    mcp.month_amount DESC,
    mcp.customer_id;