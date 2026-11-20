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
        if buyer==seller:raise ValueError('self-payment unsupported')
        if amount>(a.reserved if reserved else a.available):raise ValueError('insufficient payment funds')
        a.balance-=amount;b.balance+=amount
        if reserved:a.reserved-=amount
        self.payments[buyer]+=amount;self.receipts[seller]+=amount

    def check(self,remaining):
        for key,a in self.accounts.items():
            assert type(a.balance) is int and type(a.reserved) is int and 0<=a.reserved<=a.balance,'cash bounds'
            assert a.balance==self.initial[key]+self.receipts[key]-self.payments[key],'account flow'
            assert a.reserved==remaining.get(key,0),'reservation differs from open orders'
        assert sum(a.balance for a in self.accounts.values())==sum(self.initial.values()),'total money conservation'
