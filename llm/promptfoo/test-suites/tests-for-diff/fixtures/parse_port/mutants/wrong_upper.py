def parse_port(s):
    n = int(s)
    if not (1 <= n <= 65536):
        raise ValueError(f"port out of range: {n}")
    return n
