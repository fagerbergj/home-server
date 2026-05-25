def apply_discount(price, pct):
    pct = max(0.0, min(pct, 60.0))
    return round(price * (1 - pct / 100), 2)
