# Work Item Classification

Classify each epic based on its Credit Ratio and Revenue Ratio.

## Thresholds

| Type | Credit Ratio (L2/L1) | Revenue Ratio (L3/L1) | Label | Strategy |
|------|----------------------|------------------------|-------|----------|
| 黃金工項 | > 2.0 | > 0.3 d/h | 多接、主導 | High internal credit + high client value |
| 政治型 | > 2.0 | < 0.15 d/h | 升遷有用 | High internal credit, low client value |
| 苦工型 | < 1.2 | < 0.15 d/h | 少接 | Low credit, low client value |
| 商業槓桿 | 1.2–2.0 | > 0.3 d/h | 往 solution 走 | Medium credit, high client value |

## Ratio Definitions

- **Credit Ratio** = `SUM(internal_hours) / SUM(actual_hours)` — how much internal credit per hour of real work
- **Revenue Ratio** = `SUM(client_days) / SUM(actual_hours)` — how many client days per hour of real work
- **Pricing Leverage** = `SUM(client_days) / SUM(internal_hours)` — company markup from internal to client

## Notes

- Thresholds are initial estimates based on consulting industry norms
- Revisit after accumulating 4+ weeks of data
- Epics with insufficient L2/L3 data should be flagged, not classified
