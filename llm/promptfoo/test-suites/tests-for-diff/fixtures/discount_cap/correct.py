def apply_discount(price, pct):
    pct = max(0.0, min(pct, 50.0))  # cap discount between 0 and 50%
    return round(price * (1 - pct / 100), 2)
