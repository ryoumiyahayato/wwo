"""Streaming observation only. No decisions or authority updates."""
from collections import defaultdict
from copy import deepcopy
import csv,hashlib,json,time,gc
from pathlib import Path


def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False)

def dump(path,value):Path(path).write_text(json.dumps(value,sort_keys=True,indent=2)+'\n',encoding='utf-8')

class AppendArchive:
    """Length preserves original engine IDs; retains only current day's tail."""
    def __init__(self):self.count=0;self.base=0;self.tail=[]
    def __len__(self):return self.count
    def append(self,value):self.tail.append(value);self.count+=1
    def extend(self,values):
        for value in values:self.append(value)
    def __delitem__(self,key):
        if not isinstance(key,slice) or key.stop is not None or key.step is not None:raise ValueError('tail rollback only')
        first=key.start or 0
        if not self.base<=first<=self.count:raise ValueError('historical archive mutation')
        del self.tail[first-self.base:];self.count=first
    def clear_day(self):self.base=self.count;self.tail.clear()

class CountedOrders(dict):
    def __init__(self):super().__init__();self.count=0
    def __len__(self):return self.count
    def __setitem__(self,key,value):
        if key not in self:self.count=max(self.count,key)
        super().__setitem__(key,value)
    def pop(self,key,default=None):
        value=super().pop(key,default)
        # Only transaction rollback removes the most recent accepted ID.
        if value is not None and key==self.count:self.count-=1
        return value
    def retire(self,key):dict.pop(self,key,None)


def authoritative(sim):
    cash={k:dict(balance=a.balance,reserved=a.reserved) for k,a in sorted(sim.economics.cash.accounts.items())} if sim.economics else {}
    return dict(day=sim.day,stock=sim.stock,cumulative=sim.cumulative,
        sinks={k:{f:s[f] for f in ('backlog','delivered','received')} for k,s in sorted(sim.sinks.items())},
        routes={k:dict(pending=sim.balances(k)[0],transit=sim.balances(k)[1],**sim.totals[k]) for k in sorted(sim.routes)},
        cash=cash,prices={':'.join(k):v for k,v in sorted(sim.economics.prices.items())} if sim.economics else {})


def physical(sim):
    value=authoritative(sim);value.pop('cash');value.pop('prices');return value

class StreamObserver:
    def __init__(self,sim,directory,mode='compact'):
        if mode not in ('compact','full','off'):raise ValueError('observer mode')
        self.sim=sim;self.path=Path(directory);self.path.mkdir(parents=True,exist_ok=True);self.mode=mode
        self.economic_hash=hashlib.sha256();self.physical_hash=hashlib.sha256();self.log_seconds=0
        self.streak=defaultdict(int);self.max_streak=defaultdict(int);self.input_allocations=defaultdict(int)
        self.price_min={};self.price_max={};self.cash_min={};self.reserved_peak={};self.stock_peak={};self.transit_peak=0
        self.event_count=0;self.events_file=(self.path/'events.jsonl').open('w',encoding='utf-8',newline='\n')
        self.daily_file=(self.path/'daily.jsonl').open('w',encoding='utf-8',newline='\n') if mode!='off' else None
        self.prices_file=(self.path/'prices.jsonl').open('w',encoding='utf-8',newline='\n') if mode!='off' else None
        self.requests_file=(self.path/'requests.jsonl').open('w',encoding='utf-8',newline='\n') if mode=='full' else None
        self.archives=[]
        dump(self.path/'initial.json',dict(case=sim.case,stock=sim.initial_firm,cash=sim.economics.cash.initial if sim.economics else {},
            recipes={f:[dict(output=r.output_commodity,output_quantity=r.output_quantity,inputs=list(r.inputs)) for r in n.recipes] for f,n in sim.firms.items()}))
        if sim.economics:sim.economics.writer=self.event
        if mode!='full':
            sim.case['archive_mode']='compact'
            for name in ('requests','quotes','round_records','plans','firm_rows','flow_rows','sink_rows','route_rows','allocation_rows','customer_rows','metric_rows','events','commitment_events','rows','shipments'):
                archive=AppendArchive();setattr(sim,name,archive);self.archives.append(archive)
            sim.orders=CountedOrders()

    def event(self,record):
        t=time.perf_counter();self.events_file.write(canonical(record)+'\n');self.event_count+=1
        self.log_seconds+=time.perf_counter()-t

    def finish_day(self):
        t=time.perf_counter();s=self.sim
        snapshot=authoritative(s);phys=deepcopy(snapshot);phys.pop('cash');phys.pop('prices')
        self.economic_hash.update((canonical(snapshot)+'\n').encode());self.physical_hash.update((canonical(phys)+'\n').encode())
        for fid,node in s.firms.items():
            if not node.active:continue
            output=sum(node.planning.get('actual',{}).values());self.streak[fid]=self.streak[fid]+1 if output==0 else 0
            self.max_streak[fid]=max(self.max_streak[fid],self.streak[fid])
        requests=s.requests if self.mode=='full' else s.requests.tail
        for r in requests:
            if r['request_day']!=s.day:continue
            self.input_allocations[f'{r["buyer_id"]}:{r["commodity"]}:{r["supplier_id"]}']+=r['accepted_quantity']
            if self.requests_file:self.requests_file.write(canonical(r)+'\n')
        for fid,goods in s.stock.items():
            for g,v in goods.items():key=f'{fid}:{g}';self.stock_peak[key]=max(self.stock_peak.get(key,0),v)
        self.transit_peak=max(self.transit_peak,sum(s.balances(r)[1] for r in s.routes))
        if s.economics:
            e=s.economics
            for key,v in e.prices.items():
                k=':'.join(key);self.price_min[k]=min(self.price_min.get(k,v),v);self.price_max[k]=max(self.price_max.get(k,v),v)
            for key,a in e.cash.accounts.items():
                self.cash_min[key]=min(self.cash_min.get(key,a.balance),a.balance);self.reserved_peak[key]=max(self.reserved_peak.get(key,0),a.reserved)
            if self.prices_file:
                for r in e.price_records:
                    if r['day']==s.day:self.prices_file.write(canonical(r)+'\n')
            if self.mode!='full':e.price_records.clear()
        if self.daily_file:
            snapshot['production']={f:dict(s.firms[f].planning.get('actual',{})) for f in s.active_firms}
            snapshot['rejections']=dict(s.economics.rejections) if s.economics else {}
            snapshot['bound_hits']=dict(s.economics.price_hits) if s.economics else {}
            self.daily_file.write(canonical(snapshot)+'\n')
        if self.mode!='full':
            live={oid for orders in s.active_orders.values() for oid in orders}|set(s.cancel_requests)
            for oid in list(dict.keys(s.orders)):
                if oid not in live:
                    s.orders.retire(oid);s.commitments.pop(oid,None);s.expected_arrival.pop(oid,None);s.order_request.pop(oid,None);s.cancelled_by_order_id.pop(oid,None)
            s.requests_by_day.clear()
            for node in s.firms.values():
                book=node.release
                # All below are report archives or counters; active buckets,
                # supplies, allocations and last_timely_lineage remain intact.
                for name in ('revisions','forward_events','expired'):getattr(book,name).clear()
                for name in ('revisions_by_day','forward_by_day','release_by_day','execution_snapshots','reconciliation_by_day'):getattr(book,name).clear()
            for archive in self.archives:archive.clear_day()
        self.log_seconds+=time.perf_counter()-t

    def close(self):
        s=self.sim;e=s.economics
        final=authoritative(s)
        final['open_orders']=[dict(id=o.id,route=o.route,quantity=o.quantity,pending=o.pending_dispatch,delivered=o.delivered,cancelled=o.cancelled,
            shipments=[dict(id=c.id,quantity=c.quantity,arrival_day=c.arrival_day) for c in o.active_shipments.values()]) for orders in s.active_orders.values() for o in orders.values()]
        if e:final['financial']={str(oid):f for oid,f in e.financial.items() if f['reserved_value']};final['closed_financial']=e.closed
        dump(self.path/'final.json',final)
        for handle in (self.events_file,self.daily_file,self.prices_file,self.requests_file):
            if handle:handle.close()
        return dict(case_id=s.case['case_id'],suite=s.case.get('suite','probe'),days=s.day,mode=e.mode if e else 'N0',scale=s.case['scale'],treatment=s.case['treatment'],
            funding=e.config['funding'] if e else 'not_applicable',delivered=s.cumulative['terminal_delivered'],backlog=s.backlog,
            sinks=final['sinks'],max_nonproduction_days=dict(self.max_streak),input_allocations=dict(self.input_allocations),stock_peak=self.stock_peak,transit_peak=self.transit_peak,
            cash=final['cash'],cash_min=self.cash_min,reserved_peak=self.reserved_peak,prices=final['prices'],price_min=self.price_min,price_max=self.price_max,
            rejections=dict(e.rejections) if e else {},bound_hits=dict(e.price_hits) if e else {},
            economic_sha256=self.economic_hash.hexdigest(),physical_sha256=self.physical_hash.hexdigest(),events=self.event_count,
            implementation_gate='PASS',model_result='INCONCLUSIVE')
