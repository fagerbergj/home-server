def parse_port(s):
    # parse a TCP port string; must be an integer in 1..65535
    n = int(s)
    if not (1 <= n <= 65535):
        raise ValueError(f"port out of range: {n}")
    return n
