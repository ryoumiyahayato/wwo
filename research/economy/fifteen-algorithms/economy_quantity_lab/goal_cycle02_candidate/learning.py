"""One optional local quote candidate; inherited settlement and CashAccounts.

Seller learns only when its entire real accepted window is zero despite observed
PRICE refusal and its own positive physical stock. It never reads buyer limits.
"""
from pathlib import Path
import sys
from dataclasses import asdict
from collections import defaultdict
from copy import deepcopy
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'goal_cycle02'))
from causal import CausalSimulation
from payment_policy import PaymentPolicy
from pricing import update_price,LocalWindow
from cash import integer

VERSION='local-zero-accept-refusal-bound-v1'

def local_quote(current,initial,tick,window,accepted,previous_ceiling,enabled=True):
    integer(accepted);integer(previous_ceiling,1)
    base=update_price(current,initial,tick,window)
    low=((initial+4*tick-1)//(4*tick))*tick;high=4*initial
    if previous_ceiling%tick or not low<=previous_ceiling<=high:raise ValueError('invalid local ceiling')
    ceiling=previous_ceiling;learned=False
    if enabled and window.information_count:
        if window.price_refused and accepted==0 and window.free_stock>0 and window.cash_refused==0:
            ceiling=max(low,min(previous_ceiling,current-tick));learned=ceiling<previous_ceiling
        target=min(base['price'],ceiling)
        price=max(low,current-base['step'],min(high,current+base['step'],target))
    else:price=base['price'] if not enabled else current
    result=dict(base)
    if price!=base['price']:result['reason']='LEARNED_REFUSAL_BOUND'
    result.update(price=price,base_reason=base['reason'],base_price=base['price'],refusal_ceiling=ceiling,ceiling_learned=learned,candidate=VERSION)
    return result

class LearningPolicy(PaymentPolicy):
    @classmethod
    def wrap(cls,existing,config):
        # Share the one existing authoritative CashAccounts and all physical/
        # financial objects. No second balances object or runtime is constructed.
        self=object.__new__(cls);self.__dict__=existing.__dict__
        self.config=deepcopy(config);self.mode='N4_EXPERIMENTAL'
        self.refusal_ceiling={key:4*p for key,p in self.initial_prices.items()}
        self.window_accepts=defaultdict(int)
        return self

    def request_result(self,response,physical_cap,financial_cap,current_need):
        super().request_result(response,physical_cap,financial_cap,current_need)
        self.window_accepts[(response['supplier_id'],response['commodity'])]+=response['accepted_quantity']

    def end_day(self):
        if not self.config.get('feedback',True) or self.sim.day%7:return
        next_prices={}
        for key,w in sorted(self.windows.items()):
            seller,good=key;free=self.sim.stock_commitments.uncommitted(seller,good,self.sim.stock[seller][good])
            active=[v for v in w['interest'].values() if v['date']>=self.sim.day]
            signals=LocalWindow(free,w['shipped'],*(sum(v[r] for v in active) for r in ('PHYSICAL','PRICE_LIMIT','CASH')),len(w['information']))
            result=local_quote(self.prices[key],self.initial_prices[key],self.tick,signals,self.window_accepts[key],self.refusal_ceiling[key],self.config.get('candidate_enabled',True))
            self.refusal_ceiling[key]=result['refusal_ceiling'];next_prices[key]=result['price']
            self.price_hits['lower']+=int(result['lower_hit']);self.price_hits['upper']+=int(result['upper_hit'])
            if self.observation:self.price_records.append(dict(day=self.sim.day,effective_day=self.sim.day+1,seller=seller,commodity=good,old_price=self.prices[key],accepted_quantity=self.window_accepts[key],**result,**asdict(signals)))
            self.windows[key]=dict(shipped=0,interest={},information=set())
        self.window_accepts.clear();self.pending_prices[self.sim.day+1]=next_prices

class LearningSimulation(CausalSimulation):
    def __init__(self,case):
        temp=deepcopy(case);temp['economics']['mode']='N3'
        super().__init__(temp)
        original_cash=self.economics.cash
        self.case=deepcopy(case)
        self.economics=LearningPolicy.wrap(self.economics,case['economics'])
        assert self.economics.cash is original_cash
        assert all(n.cash_account is self.economics.cash.accounts[f] for f,n in self.firms.items())
