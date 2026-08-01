"""Money is always integer paise. Floats never touch an amount; Pydantic enforces
strict ints at the API boundary, this module owns the few conversions that exist."""

type Paise = int


def format_inr(paise: Paise) -> str:
    """Indian-grouped rupee string for exports: 123456789 -> '₹12,34,567.89'.
    Display formatting for screens stays in the app; this is for CSV and logs."""
    sign = "-" if paise < 0 else ""
    rupees, p = divmod(abs(paise), 100)
    s = str(rupees)
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        groups: list[str] = []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        if head:
            groups.insert(0, head)
        s = ",".join([*groups, tail])
    return f"{sign}₹{s}.{p:02d}"
