"""Single authoritative integer balance map. Reserved is inside balance."""
from collections import defaultdict
from dataclasses import dataclass


def integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError('expected explicit integer monetary/quantity unit')
    return value


@dataclass
class Account:
    balance: int
    reserved: int = 0
    @property
    def available(self): return self.balance-self.reserved


class CashAccounts:
    def __init__(self, balances):
        self.accounts={k:Account(integer(v)) for k,v in balances.items()}
        self.initial=dict(balances)
        self.receipts=defaultdict(int);self.payments=defaultdict(int)

    def reserve(self, buyer, amount):
        integer(amount,1);a=self.accounts[buyer]
        if amount>a.available:raise ValueError('insufficient available cash')
        a.reserved+=amount

    def release(self,buyer,amount):
        integer(amount,1);a=self.accounts[buyer]
        if amount>a.reserved:raise ValueError('release beyond reserved')
        a.reserved-=amount

    def pay(self,buyer,seller,amount,reserved=False):
        integer(amount,1);a=self.accounts[buyer];b=self.accounts[seller]
        currencies=getattr(self,'currency_by_account',None)
        if currencies and currencies[buyer]!=currencies[seller]:raise ValueError('cross-currency payment requires exchange legs')
        if buyer==seller:raise ValueError('self-payment unsupported')
        if amount>(a.reserved if reserved else a.available):raise ValueError('insufficient payment funds')
        a.balance-=amount;b.balance+=amount
        if reserved:a.reserved-=amount
        self.payments[buyer]+=amount;self.receipts[seller]+=amount

    def batch_pay(self,legs,fail_after=None):
        """Atomic existing-money legs; preserve authoritative Account objects."""
        debits=defaultdict(int)
        for buyer,seller,amount in legs:
            integer(amount,1)
            if buyer==seller or buyer not in self.accounts or seller not in self.accounts:raise ValueError('invalid batch parties')
            currencies=getattr(self,'currency_by_account',None)
            if currencies and currencies[buyer]!=currencies[seller]:raise ValueError('batch currency mismatch')
            debits[buyer]+=amount
        if any(q>self.accounts[k].available for k,q in debits.items()):raise ValueError('unfunded batch')
        keys={k for leg in legs for k in leg[:2]}
        before={k:(self.accounts[k].balance,self.accounts[k].reserved,self.payments[k],self.receipts[k]) for k in keys}
        try:
            for index,(buyer,seller,q) in enumerate(legs):
                self.pay(buyer,seller,q)
                if fail_after==index+1:raise RuntimeError('injected batch failure')
        except Exception:
            for k,(balance,reserved,paid,received) in before.items():
                self.accounts[k].balance=balance;self.accounts[k].reserved=reserved;self.payments[k]=paid;self.receipts[k]=received
            raise

    def check(self,remaining):
        for key,a in self.accounts.items():
            assert type(a.balance) is int and type(a.reserved) is int and 0<=a.reserved<=a.balance,'cash bounds'
            assert a.balance==self.initial[key]+self.receipts[key]-self.payments[key],'account flow'
            assert a.reserved==remaining.get(key,0),'reservation differs from open orders'
        currencies=getattr(self,'currency_by_account',None)
        if currencies:
            for currency in set(currencies.values()):
                assert sum(a.balance for k,a in self.accounts.items() if currencies[k]==currency)==sum(v for k,v in self.initial.items() if currencies[k]==currency),'currency conservation'
        else:assert sum(a.balance for a in self.accounts.values())==sum(self.initial.values()),'total money conservation'
