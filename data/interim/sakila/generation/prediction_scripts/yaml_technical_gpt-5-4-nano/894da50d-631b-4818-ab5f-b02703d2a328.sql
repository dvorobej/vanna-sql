WITH base AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    cp.p01 AS payment_id,
    cp.p05 AS payment_amount,
    cp.p06 AS payment_ts,
    strftime('%Y-%m', cp.p06) AS month_ym,
    cp.p03 AS staff_id,
    st.o07 AS staff_store_id,
    r.q06 AS staff_branch_id_dummy, -- not used directly;