def paginate(items, page, size):
    # page is 1-based; raise on bad args, return [] when out of range
    if page < 1 or size < 1:
        raise ValueError("page and size must be >= 1")
    start = (page - 1) * size
    return items[start:start + size]
