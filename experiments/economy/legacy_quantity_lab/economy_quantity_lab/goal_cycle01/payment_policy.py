"""Opt-in composition on Round6 hooks; physical settlement remains inherited."""
from collections import defaultdict
from copy import deepcopy
from dataclasses import dataclass,asdict
from cash import CashAccounts,integer
from pricing import LocalWindow,update_price
from stock_admission import SupplierOffer
from multi_supplier import ranked_offers

@dataclass(frozen=True)
class PricedOffer(SupplierOffer):
    posted_price: int = 1

class PaymentPolicy:
    def __init__(self,sim,config):
        self.sim=sim;self.config=deepcopy(config);self.mode=config['mode']
        if self.mode not in ('N1','N2','N3'):raise ValueError('unknown price mode')
        self.cash=CashAccounts(config['balances']);self.prices={tuple(k.split(':')):integer(v,1) for k,v in config['prices'].items()}
        self.initial_prices=dict(self.prices);self.tick=integer(config.get('tick',1),1)
        self.financial={};self.paid_shipments=set();self.closed=dict(orders=0,value=0,paid=0,cancelled=0)
        self.records=[];self.writer=self.records.append;self.transaction=None;self.failpoint=None
        self.pending_prices={};self.windows={};self.price_records=[];self.rejections=defaultdict(int)
        self.price_hits=defaultdict(int);self.observation=config.get('price_observer',True)
        self.price_events=defaultdict(list)
        for e in config.get('price_events',[]):self.price_events[e['day']].append(e)
        for fid,node in sim.firms.items():node.cash_account=self.cash.accounts[fid]
        for key in self.prices:self.windows[key]=dict(shipped=0,interest={},information=set())

    def emit(self,event,**fields):
        record=dict(day=self.sim.day,event=event,**fields)
        if self.transaction is not None:self.transaction.append(record)
        else:self.writer(record)

    def quote(self,offer):
        return PricedOffer(**asdict(offer),posted_price=self.prices[(offer.supplier_id,offer.commodity)])

    def rank(self,offers):
        if self.mode=='N1':return ranked_offers(offers)
        # Date feasibility remains in ReleaseBook.executable, before intent.
        return sorted(offers,key=lambda o:(o.posted_price,o.expected_arrival_day,-o.max_acceptable_quantity,o.supplier_id))

    def limit(self,request,physical):
        price=self.prices[(request['supplier_id'],request['commodity'])]
        limit=self.config['limits'][request['buyer_id']][request['commodity']]
        integer(limit,1)
        return min(physical,self.cash.accounts[request['buyer_id']].available//price) if price<=limit else 0

    def accept(self,route,quantity,quote):
        """Reserve all three resources, then call the unchanged engine acceptance.

        The undo journal is limited to this route/order and append tails. Event
        output is buffered until commit, so injected failures cannot leak logs.
        """
        integer(quantity,1);s=self.sim;r=s.routes[route];price=self.prices[(r.seller_id,r.commodity)]
        if price>self.config['limits'][r.buyer_id][r.commodity]:raise ValueError('above limit')
        oid=len(s.orders)+1;slots=s.route_slots[route];stock=s.stock_commitments
        # Preflight all current authority checks; no quote is itself a reservation.
        if quantity>min(stock.uncommitted(r.seller_id,r.commodity,s.stock[r.seller_id][r.commodity]),sum(v['remaining_slot'] for v in quote),self.cash.accounts[r.buyer_id].available//price):raise ValueError('acceptance resources changed')
        before=dict(slots=deepcopy(vars(slots)),entries=deepcopy(stock.entries),totals=deepcopy(stock.totals),
                    route_totals=dict(s.totals[route]),customer=s.firms[r.seller_id].customer_pending[r.commodity],
                    events=len(s.events),commitment_events=len(s.commitment_events),reserved=self.cash.accounts[r.buyer_id].reserved)
        self.transaction=[]
        def fail(stage):
            if self.failpoint==stage:raise RuntimeError('injected acceptance failure:'+stage)
        try:
            stock.reserve(oid,r.seller_id,r.commodity,quantity,s.stock[r.seller_id][r.commodity]);fail('stock')
            self.cash.reserve(r.buyer_id,quantity*price);fail('cash')
            slots.reserve(oid,quantity,quote);fail('slots')
            self.financial[oid]=dict(buyer=r.buyer_id,seller=r.seller_id,commodity=r.commodity,locked_price=price,
                quantity=quantity,original_value=quantity*price,paid_value=0,reserved_value=quantity*price,cancelled_value=0,paid_shipment_ids=[])
            order=s.accept_order(route,quantity);fail('order')
            self.emit('accepted',order_id=oid,route=route,buyer=r.buyer_id,seller=r.seller_id,commodity=r.commodity,quantity=quantity,locked_price=price,reserved_value=quantity*price)
        except Exception:
            vars(slots).clear();vars(slots).update(before['slots']);stock.entries=before['entries'];stock.totals=before['totals']
            self.cash.accounts[r.buyer_id].reserved=before['reserved'];self.financial.pop(oid,None)
            s.orders.pop(oid,None);s.active_orders[route].pop(oid,None)
            if s.dispatch_queues[route] and s.dispatch_queues[route][-1].id==oid:s.dispatch_queues[route].pop()
            s.commitments.pop(oid,None);s.expected_arrival.pop(oid,None);s.totals[route]=before['route_totals']
            s.firms[r.seller_id].customer_pending[r.commodity]=before['customer']
            del s.events[before['events']:];del s.commitment_events[before['commitment_events']:]
            self.transaction=None
            raise
        records=self.transaction;self.transaction=None
        for record in records:self.writer(record)
        return order

    def order_event(self,event,order,shipment,quantity):
        if event=='accepted':return # committed acceptance emitted by transaction
        f=self.financial[order.id];s=self.sim
        if event=='dispatched':
            self.windows[(f['seller'],f['commodity'])]['shipped']+=quantity
            self.emit('dispatched',order_id=order.id,shipment_id=shipment.id,quantity=quantity,arrival_day=shipment.arrival_day)
        elif event=='arrived':
            if shipment.id in f['paid_shipment_ids']:raise ValueError('duplicate arrival payment')
            value=quantity*f['locked_price']
            self.cash.pay(f['buyer'],f['seller'],value,reserved=True)
            f['paid_value']+=value;f['reserved_value']-=value;f['paid_shipment_ids'].append(shipment.id)
            self.emit('arrived',order_id=order.id,shipment_id=shipment.id,quantity=quantity)
            self.emit('payment',order_id=order.id,shipment_id=shipment.id,buyer=f['buyer'],seller=f['seller'],
                      quantity=quantity,locked_price=f['locked_price'],buyer_debit=value,seller_credit=value,reserved_release=value)
        elif event=='cancelled':
            value=quantity*f['locked_price'];self.cash.release(f['buyer'],value)
            f['cancelled_value']+=value;f['reserved_value']-=value
            self.emit('cancelled',order_id=order.id,quantity=quantity,released_value=value)
        if not f['reserved_value']:
            assert f['original_value']==f['paid_value']+f['cancelled_value']
            self.closed['orders']+=1;self.closed['value']+=f['original_value'];self.closed['paid']+=f['paid_value'];self.closed['cancelled']+=f['cancelled_value']
            if s.case.get('archive_mode') in ('compact','off'):del self.financial[order.id]

    def terminal_quantity(self,sink,quantity):
        sid=sink['sink_id'];p=self.config['terminal_prices'][sid];integer(p,1)
        cap=self.cash.accounts['external:'+sid].available//p
        if quantity>cap:self.rejections['TERMINAL_CASH']+=quantity-cap
        return min(quantity,cap)

    def terminal_payment(self,sink,quantity):
        if not quantity:return
        sid=sink['sink_id'];buyer='external:'+sid;seller=sink['firm_id'];p=self.config['terminal_prices'][sid];value=quantity*p
        self.cash.pay(buyer,seller,value)
        self.emit('terminal',sink_id=sid,buyer=buyer,seller=seller,commodity=sink['commodity'],quantity=quantity,locked_price=p,buyer_debit=value,seller_credit=value)

    def request_result(self,response,physical_cap,financial_cap,current_need):
        buyer=response['buyer_id'];seller=response['supplier_id'];good=response['commodity'];requested=response['requested_quantity'];q=response['accepted_quantity']
        price=self.prices[(seller,good)];physical=min(requested,physical_cap)
        reasons=dict(PHYSICAL=requested-q,PRICE_LIMIT=0,CASH=0)
        economic=min(requested-q,max(0,physical-financial_cap))
        reasons['PRICE_LIMIT' if price>self.config['limits'][buyer][good] else 'CASH']=economic
        reasons['PHYSICAL']-=economic
        stale=min(reasons['PHYSICAL'],max(0,requested-current_need))
        reasons['PHYSICAL']-=stale;reasons['STALE_NEED']=stale
        response.update(posted_price=price,rejections=reasons,financially_uncovered_need=reasons['CASH'],price_uncovered_need=reasons['PRICE_LIMIT'])
        for reason,value in reasons.items():self.rejections[reason]+=value
        reasons=dict(reasons)
        w=self.windows[(seller,good)];left_accepted=q
        for line in response['lines']:
            take=min(left_accepted,line['quantity']);left_accepted-=take
            rem=line['quantity']-take
            key=(buyer,line['need_id']);w['information'].add(key)
            state=w['interest'].setdefault(key,dict(date=line['need_by_day'],PHYSICAL=0,PRICE_LIMIT=0,CASH=0))
            state['date']=max(state['date'],line['need_by_day'])
            # Allocate exclusive rejection explanations to actual public lines.
            for reason in ('PHYSICAL','PRICE_LIMIT','CASH'):
                part=min(rem,reasons[reason]);state[reason]=max(state[reason],part);rem-=part;reasons[reason]-=part

    def begin_day(self):
        for key,value in sorted(self.pending_prices.pop(self.sim.day,{}).items()):self.prices[key]=value
        for e in self.price_events.pop(self.sim.day,[]):
            key=(e['seller'],e['commodity']);self.prices[key]=integer(e['price'],1)

    def end_day(self):
        if self.mode!='N3' or not self.config.get('feedback',True) or self.sim.day%7:return
        next_prices={}
        for key,w in sorted(self.windows.items()):
            seller,good=key;free=self.sim.stock_commitments.uncommitted(seller,good,self.sim.stock[seller][good])
            active=[v for v in w['interest'].values() if v['date']>=self.sim.day]
            signals=LocalWindow(free,w['shipped'],*(sum(v[r] for v in active) for r in ('PHYSICAL','PRICE_LIMIT','CASH')),len(w['information']))
            result=update_price(self.prices[key],self.initial_prices[key],self.tick,signals);next_prices[key]=result['price']
            self.price_hits['lower']+=int(result['lower_hit']);self.price_hits['upper']+=int(result['upper_hit'])
            if self.observation:self.price_records.append(dict(day=self.sim.day,effective_day=self.sim.day+1,seller=seller,commodity=good,old_price=self.prices[key],**result,**asdict(signals)))
            self.windows[key]=dict(shipped=0,interest={},information=set())
        self.pending_prices[self.sim.day+1]=next_prices

    def check(self):
        remaining=defaultdict(int)
        for oid,f in self.financial.items():
            assert f['original_value']==f['paid_value']+f['reserved_value']+f['cancelled_value'],'order financial identity'
            o=self.sim.orders[oid]
            assert f['reserved_value']==(o.pending_dispatch+o.in_transit)*f['locked_price'],'order financial quantity'
            remaining[f['buyer']]+=f['reserved_value']
        self.cash.check(remaining)
