def parse_port(s):
    n = int(s)
    if not (0 <= n <= 65535):
        raise ValueError(f"port out of range: {n}")
    return n
