def apply_discount(price, pct):
    pct = min(pct, 50.0)
    return round(price * (1 - pct / 100), 2)
