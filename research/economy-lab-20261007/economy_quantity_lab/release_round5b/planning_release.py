"""Active execution buckets, dated coverage and current-offer release decisions."""
from collections import defaultdict
from dataclasses import dataclass, asdict


@dataclass
class RequirementBucket:
    producer: str
    commodity: str
    need_by_day: int
    requirement_class: str
    quantity: int
    basis: str
    created_day: int
    last_revised_day: int
    previous_qty: int
    revision_delta: int
    release_by_day: int

    @property
    def bucket_id(self):
        return f"{self.producer}:{self.commodity}:{self.need_by_day}:{self.requirement_class}"

    @property
    def pool(self): return self.producer,self.commodity

    def record(self):
        return dict(requirement_bucket_id=self.bucket_id,**asdict(self),
                    projected_qty=self.quantity if self.requirement_class=="PROJECTED" else 0,
                    firm_qty=self.quantity if self.requirement_class=="FIRM" else 0)


class ReleaseBook:
    """Non-owning supply reconciliation. Archives never participate in decisions."""
    def __init__(self):
        self.active={}; self.first_seen={}; self.revisions=[]; self.revisions_by_day=defaultdict(list)
        self.allocations=[]; self.by_bucket=defaultdict(list); self.by_lot=defaultdict(list)
        self.supplies={}; self.unallocated=[]; self.forward_events=[]; self.forward_by_day=defaultdict(list)
        self.expired=[]; self.release_checks=0; self.allocation_candidates=0
        self.last_timely_lineage={}; self.absolute_seen=set()
        self.execution_snapshots={}; self.release_by_day=defaultdict(list); self.reconciliation_by_day={}

    def revise(self,day,records,conservative_lead):
        incoming={}; physical=set()
        for producer,commodity,date,klass,qty,basis in records:
            if klass not in ("FIRM","PROJECTED") or qty<0 or date<day: raise ValueError("invalid active bucket")
            identity=(producer,commodity,date)
            if identity in physical: raise ValueError("duplicate absolute-date execution responsibility")
            physical.add(identity)
            key=f"{producer}:{commodity}:{date}:{klass}"
            old=self.active.get(key)
            other="PROJECTED" if klass=="FIRM" else "FIRM"
            promoted=self.active.get(f"{producer}:{commodity}:{date}:{other}")
            previous=old or promoted
            created=previous.created_day if previous else self.first_seen.setdefault(key,day)
            self.first_seen.setdefault(key,created); self.absolute_seen.add(identity)
            previous_qty=previous.quantity if previous else 0
            bucket=RequirementBucket(producer,commodity,date,klass,qty,basis,created,day,
                                     previous_qty,qty-previous_qty,date-conservative_lead)
            incoming[key]=bucket
            event=dict(day=day,event="CLASS_TRANSITION" if promoted else "REVISION" if old else "CREATED",
                       **bucket.record(),revised_qty=qty)
            self.revisions.append(event); self.revisions_by_day[day].append(event)
        for key,old in self.active.items():
            identity=(old.producer,old.commodity,old.need_by_day)
            if key not in incoming and identity not in physical:
                event=dict(day=day,event="OUTSIDE_VISIBILITY",**old.record(),revised_qty=0,
                           visible_revision_delta=-old.quantity)
                self.revisions.append(event); self.revisions_by_day[day].append(event)
        self.active=incoming
        assert len(self.active)==len(physical)

    def reconcile(self,day,supplies):
        supplies=list(supplies)
        if len({s.supply_id for s in supplies})!=len(supplies): raise ValueError("duplicate supply lot")
        if any(s.quantity<0 for s in supplies): raise ValueError("negative supply")
        self.supplies={s.supply_id:s for s in supplies}
        self.allocations=[]; self.by_bucket=defaultdict(list); self.by_lot=defaultdict(list)
        remaining={s.supply_id:s.quantity for s in supplies}
        ordered=sorted(supplies,key=lambda s:(s.available_day is None,s.available_day or 0,s.supply_id))
        for bucket in sorted(self.active.values(),key=lambda b:(b.need_by_day,b.bucket_id)):
            gap=bucket.quantity
            for lot in ordered:
                self.allocation_candidates+=1
                if not gap: break
                if (lot.producer_id,lot.commodity)!=bucket.pool: continue
                if lot.available_day is None or lot.available_day>bucket.need_by_day: continue
                q=min(gap,remaining[lot.supply_id])
                if not q: continue
                record=dict(bucket_id=bucket.bucket_id,need_by_day=bucket.need_by_day,
                            requirement_class=bucket.requirement_class,lot_id=lot.supply_id,
                            available_by_day=lot.available_day,quantity=q,kind=lot.kind,order_id=lot.order_id)
                self.allocations.append(record); self.by_bucket[bucket.bucket_id].append(record)
                self.by_lot[lot.supply_id].append(record); remaining[lot.supply_id]-=q; gap-=q
        # Retain a live lot/order's last timed assignment through an UNKNOWN
        # interval. This index is pruned at receipt/cancel, never an archive scan.
        live_lineages={("lot",s.supply_id) for s in supplies if s.kind!="ON_HAND"}
        live_lineages.update(("pending_order",s.order_id) for s in supplies if s.order_id is not None)
        previous={k:v for k,v in self.last_timely_lineage.items() if k in live_lineages}
        self.last_timely_lineage=dict(previous)
        for lot in supplies:
            lineage=("lot",lot.supply_id)
            if lot.kind=="ON_HAND": continue
            old=previous.get(lineage,[])
            if not old and lot.kind=="IN_TRANSIT" and lot.order_id is not None:
                old=previous.get(("pending_order",lot.order_id),[])
            new=self.by_lot[lot.supply_id]
            if old and new and lot.available_day is not None:
                old_day=min(a["need_by_day"] for a in old); new_day=min(a["need_by_day"] for a in new)
                old_available=min(a["available_by_day"] for a in old)
                if lot.available_day>old_available and new_day>old_day:
                    event=dict(day=day,lot_id=lot.supply_id,order_id=lot.order_id,event="FORWARD_REASSIGNED",
                               old_need_by=old_day,new_need_by=new_day,available_by=lot.available_day,
                               quantity=sum(a["quantity"] for a in new))
                    self.forward_events.append(event); self.forward_by_day[day].append(event)
            if new:
                self.last_timely_lineage[lineage]=[dict(a) for a in new]
                if lot.kind=="ACCEPTED_PENDING" and lot.order_id is not None:
                    self.last_timely_lineage[("pending_order",lot.order_id)]=[dict(a) for a in new]
        self.unallocated=[dict(lot_id=s.supply_id,producer=s.producer_id,commodity=s.commodity,
                               quantity=remaining[s.supply_id],available_by_day=s.available_day,kind=s.kind,
                               order_id=s.order_id,state="UNALLOCATED_EXPOSURE")
                          for s in supplies if remaining[s.supply_id]]
        assert all(a["available_by_day"]<=a["need_by_day"] for a in self.allocations)
        assert all(sum(a["quantity"] for a in self.by_lot[s.supply_id])<=s.quantity for s in supplies)

    def gap(self,key):
        return max(0,self.active[key].quantity-sum(a["quantity"] for a in self.by_bucket[key]))

    def visible(self,pool): return sum(b.quantity for b in self.active.values() if b.pool==pool)
    def exposure(self,pool): return sum(s.quantity for s in self.supplies.values() if (s.producer_id,s.commodity)==pool)

    def ceiling_room(self,pool,safety_target):
        return max(0,max(safety_target,self.visible(pool))-self.exposure(pool))

    def excess(self,pool): return max(0,self.exposure(pool)-self.visible(pool))

    def executable(self,day,pool,offer,reserved=None,due_only=True,record=True):
        reserved=reserved or {}; result=[]
        lead=offer.expected_arrival_day-day
        if lead<0 or offer.offer_day!=day: raise ValueError("only current offer may release procurement")
        for b in sorted(self.active.values(),key=lambda b:(b.need_by_day,b.bucket_id)):
            if b.pool!=pool: continue
            self.release_checks+=1
            release=b.need_by_day-lead
            timely=offer.expected_arrival_day<=b.need_by_day
            due=release<=day
            gap=max(0,self.gap(b.bucket_id)-reserved.get(b.bucket_id,0))
            q=gap if timely and (due or not due_only) else 0
            if record:
                self.release_by_day[day].append(dict(day=day,bucket_id=b.bucket_id,
                    supplier_id=offer.supplier_id,requirement_class=b.requirement_class,need_by_day=b.need_by_day,
                    conservative_supply_lead=lead,release_by_day=release,offer_arrival=offer.expected_arrival_day,
                    timely=timely,release_due=due,gap=gap,executable_qty=q))
            if q: result.append((b.bucket_id,q))
        return result

    def consume(self,day,actual_inputs):
        remaining=dict(actual_inputs)
        for key,b in list(self.active.items()):
            if b.need_by_day>day: continue
            if b.requirement_class!="FIRM": raise AssertionError("projected tail cannot be consumed as production")
            q=min(b.quantity,remaining.get(b.pool,0)); remaining[b.pool]=remaining.get(b.pool,0)-q
            self.expired.append(dict(day=day,**b.record(),consumed=q,expired_unfulfilled=b.quantity-q))
            del self.active[key]

    def snapshot(self):
        return [dict(**b.record(),allocated=sum(a["quantity"] for a in self.by_bucket[b.bucket_id]),
                     timely_gap=self.gap(b.bucket_id)) for b in self.active.values()]


def need_components(safety_gap,release_gap,ceiling_room):
    # The unchanged safety target and due plan gap share replenishment units.
    # A due timely gap gates release; it does not turn projected tail into safety.
    total=max(0,min(max(safety_gap,release_gap),ceiling_room)) if release_gap>0 else 0
    safety=min(max(0,safety_gap),total)
    return dict(procurement_need_safety=safety,procurement_need_plan=total-safety,
                procurement_need_total=total,timely_release_gap=release_gap,exposure_room=ceiling_room)
