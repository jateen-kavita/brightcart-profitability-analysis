set search_path to ecom_profit;
CREATE TABLE orders (
    order_id            VARCHAR(20) PRIMARY KEY,
    customer_id         VARCHAR(20),
    order_date          text,
    channel             VARCHAR(30),
    payment_method      VARCHAR(50),
    region              VARCHAR(50),
    items_ordered       INTEGER,
    primary_category    VARCHAR(50),
    gross_revenue       NUMERIC(12,2),
    discount_pct        NUMERIC(5,2),
    discount_amount     NUMERIC(12,2),
    shipping_cost       NUMERIC(12,2),
    product_cost        NUMERIC(12,2),
    platform_fee        NUMERIC(12,2),
    transaction_fee     NUMERIC(12,2),
    returned            VARCHAR(5),      -- 'Yes' / 'No'
    refund_amount       NUMERIC(12,2),
    net_revenue         NUMERIC(12,2),
    total_costs         NUMERIC(12,2),
    profit              NUMERIC(12,2)
);

alter table orders
alter column order_date
type date
using to_date(order_date,'yyyy/mm/dd')

CREATE TABLE marketing_spend (
    month VARCHAR(10),
    platform VARCHAR(50),
    spend DECIMAL(10, 2),
    impressions INT,
    clicks INT,
    conversions INT,
    revenue_attributed DECIMAL(10, 2),
    cpc DECIMAL(10, 2),
    cpa DECIMAL(10, 2),
    roas DECIMAL(10, 2)
);

alter table marketing_spend
alter column month
type date
using to_date(month,'yyyy/mm')

CREATE TABLE products (
    product_id              VARCHAR(20) PRIMARY KEY,
    product_name            VARCHAR(100),
    category                VARCHAR(50),
    sub_category            VARCHAR(50),
    unit_cost               NUMERIC(12,2),
    selling_price           NUMERIC(12,2),
    shipping_cost_per_unit  NUMERIC(12,2),
    weight_lbs              NUMERIC(8,2),
    supplier                VARCHAR(100)
);
-- DATA QUALITY & SANITY CHECKS
SELECT 'orders' AS table_name, COUNT(*) FROM orders
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'marketing_spend', COUNT(*) FROM marketing_spend;

-- Check missing critical values
SELECT
    COUNT(*) FILTER (WHERE net_revenue IS NULL) AS missing_net_revenue,
    COUNT(*) FILTER (WHERE product_cost IS NULL) AS missing_product_cost,
    COUNT(*) FILTER (WHERE shipping_cost IS NULL) AS missing_shipping_cost,
    COUNT(*) FILTER (WHERE profit IS NULL) AS missing_profit
FROM orders;

-- Verify cost math (MOST IMPORTANT)
SELECT
    COUNT(*) AS total_orders,
    SUM(
        CASE 
            WHEN ABS(
                total_costs -
                (product_cost + shipping_cost + platform_fee + transaction_fee)
            ) > 0.01
            THEN 1 ELSE 0
        END
    ) AS cost_mismatch_orders
FROM orders;

-- Validate profit math
SELECT
    COUNT(*) AS profit_mismatch
FROM orders
WHERE ABS(
    profit - (net_revenue - total_costs)
) > 0.01;

-- OVERALL BUSINESS PERFORMANCE (KPI FOUNDATION)
-- 2.1 Revenue, Cost, Profit
SELECT
    ROUND(SUM(gross_revenue),2) AS gross_revenue,
    ROUND(SUM(net_revenue),2) AS net_revenue,
    ROUND(SUM(total_costs),2) AS total_costs,
    ROUND(SUM(profit),2) AS total_profit,
    ROUND(SUM(profit)/SUM(net_revenue)*100,2) AS profit_margin_pct
FROM orders;


-- PRODUCT CATEGORY PROFITABILITY (CEO Q1)
-- 3.1 Category-level profit & margin

SELECT
    primary_category,
    COUNT(order_id) AS orders,
    ROUND(SUM(net_revenue),2) AS revenue,
    ROUND(SUM(total_costs),2) AS costs,
    ROUND(SUM(profit),2) AS profit,
    ROUND(SUM(profit)/SUM(net_revenue)*100,2) AS margin_pct
FROM orders
GROUP BY primary_category
ORDER BY margin_pct DESC;

-- 3.2 Cost driver breakdown by category
SELECT
    primary_category,
    ROUND(SUM(product_cost),2) AS product_cost,
    ROUND(SUM(shipping_cost),2) AS shipping_cost,
    ROUND(SUM(discount_amount),2) AS discount_amount,
    ROUND(SUM(platform_fee + transaction_fee),2) AS fees
FROM orders
GROUP BY primary_category
ORDER BY product_cost DESC;

-- SALES CHANNEL PROFITABILITY (CEO Q2)
-- 4.1 Channel performance summary
SELECT
    channel,
    COUNT(order_id) AS orders,
    ROUND(AVG(net_revenue),2) AS avg_order_value,
    ROUND(AVG(profit),2) AS avg_profit_per_order,
    ROUND(SUM(profit)/SUM(net_revenue)*100,2) AS margin_pct
FROM orders
GROUP BY channel
ORDER BY avg_profit_per_order DESC;

-- 4.2 Platform fee impact (Marketplace & Social)
SELECT
    channel,
    ROUND(SUM(platform_fee),2) AS total_platform_fees,
    ROUND(AVG(platform_fee),2) AS avg_platform_fee
FROM orders
GROUP BY channel
ORDER BY total_platform_fees DESC;

-- RETURNS DEEP DIVE (CEO Q3)
-- 5.1 Return rate by category & channel
SELECT
    primary_category,
	channel,
    ROUND(
        SUM(CASE WHEN returned = 'Yes' THEN 1 ELSE 0 END)::DECIMAL
        / COUNT(*) * 100, 2
    ) AS return_rate_pct
FROM orders
GROUP BY primary_category,channel
ORDER BY 3 DESC
limit 10

-- 5.2 Revenue lost to returns
SELECT
    primary_category,
    channel,
    ROUND(SUM(refund_amount),2) AS revenue_lost
FROM orders
WHERE returned = 'Yes'
GROUP BY primary_category, channel
ORDER BY revenue_lost DESC
limit 10;

-- 5.3 Profit erosion due to returns
SELECT
    primary_category,
    ROUND(SUM(profit),2) AS profit_after_returns,
    ROUND(SUM(
        CASE WHEN returned = 'Yes' THEN refund_amount ELSE 0 END
    ),2) AS return_impact
FROM orders
GROUP BY primary_category
ORDER BY return_impact DESC;

-- MARKETING PERFORMANCE & ROAS (CEO Q4)
-- 6.1 Platform-level ROAS
SELECT
    platform,
    ROUND(SUM(spend),2) AS spend,
    ROUND(SUM(revenue_attributed),2) AS revenue,
    ROUND(SUM(revenue_attributed)/SUM(spend),2) AS roas
FROM marketing_spend
GROUP BY platform
ORDER BY roas DESC;

-- 6.2 Blended ROAS
SELECT
    ROUND(SUM(revenue_attributed)/SUM(spend),2) AS blended_roas
FROM marketing_spend;

-- 6.3 CPA & CPC
SELECT
    platform,
    ROUND(SUM(spend)/SUM(conversions),2) AS cpa,
    ROUND(SUM(spend)/SUM(clicks),2) AS cpc
FROM marketing_spend
GROUP BY platform;

-- 6.4 Platforms below breakeven (ROAS < 8)
SELECT
    platform,
    ROUND(SUM(spend),2) AS spend,
    ROUND(SUM(revenue_attributed)/SUM(spend),2) AS roas
FROM marketing_spend
GROUP BY platform
HAVING SUM(revenue_attributed)/SUM(spend) < 8;

-- MONTHLY TREND & VOLATILITY (CEO Q5)
-- 7.1 Monthly ROAS trend
SELECT
    month,
    platform,
    ROUND(SUM(revenue_attributed)/SUM(spend),2) AS roas
FROM marketing_spend
GROUP BY month, platform
ORDER BY month, platform;

-- 7.2 ROAS volatility (risk analysis)
SELECT
    platform,
    ROUND(STDDEV(revenue_attributed/spend),2) AS roas_volatility
FROM marketing_spend
GROUP BY platform
ORDER BY roas_volatility DESC;

-- 20% BUDGET CUT RECOMMENDATION
-- 8.1 High spend + low return platforms
SELECT
    platform,
    ROUND(SUM(spend),2) AS total_spend,
    ROUND(SUM(revenue_attributed)/SUM(spend),2) AS roas
FROM marketing_spend
GROUP BY platform
HAVING SUM(revenue_attributed)/SUM(spend) < 8
ORDER BY total_spend DESC;

-- 8.2 Weak months to cut first
with mycte as (
SELECT
    month,
    platform,
    ROUND(SUM(spend),2) AS spend,
    ROUND(SUM(revenue_attributed)/SUM(spend),2) AS roas,
	rank() over(partition by month order by spend desc) as rnk
FROM marketing_spend
where extract(year from month) = 2025
GROUP BY month, platform,spend
HAVING SUM(revenue_attributed)/SUM(spend) < 8
ORDER BY month asc
)
select to_char(month,'YYYY-MM'),platform,spend,roas
from mycte
where rnk = 1