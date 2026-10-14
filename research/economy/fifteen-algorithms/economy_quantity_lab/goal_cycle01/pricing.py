"""One pure, local, completed-window feedback candidate. No world argument."""
from dataclasses import dataclass
from cash import integer

@dataclass(frozen=True)
class LocalWindow:
    free_stock: int
    shipped: int
    physical_unmet: int
    price_refused: int
    cash_refused: int
    information_count: int


def update_price(current,initial,tick,window):
    integer(current,1);integer(initial,1);integer(tick,1)
    for v in vars(window).values():integer(v)
    if current%tick or initial%tick:raise ValueError('price not on configured tick')
    low=((initial+4*tick-1)//(4*tick))*tick;high=4*initial
    step=(current*2//100//tick)*tick
    direction=0;reason='HOLD'
    if not window.information_count:reason='NO_NEW_INFORMATION'
    elif window.free_stock>=2*max(window.shipped,1):direction=-1;reason='IDLE_STOCK'
    elif (window.price_refused or window.cash_refused) and window.free_stock:direction=-1;reason='ECONOMIC_REFUSAL'
    elif window.physical_unmet and window.shipped and window.free_stock<window.shipped:direction=1;reason='OBSERVED_PHYSICAL_PRESSURE'
    proposed=current+direction*step
    result=max(low,min(high,proposed))
    return dict(price=result,reason=reason,unclamped=proposed,lower_hit=proposed<=low,upper_hit=proposed>=high,step=step)
