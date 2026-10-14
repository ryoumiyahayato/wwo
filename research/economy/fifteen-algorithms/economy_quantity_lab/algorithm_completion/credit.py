"""Funded bilateral contracts on the world's existing CashAccounts authority."""
from cash import integer

def issue(world,spec):
    lid=spec['id'];lender=spec['lender'];borrower=spec['borrower'];p=integer(spec['principal'],1);interest=integer(spec.get('interest',0));due=integer(spec['due_day'],1)
    if lid in world.loans or due<=world.day:raise ValueError('duplicate/expired loan contract')
    if spec.get('requires_job',True) and borrower not in world.contracts:
        world.emit('loan_rejected',loan_id=lid,reason='NO_CURRENT_JOB');return False
    if lender not in world.households[borrower].get('known_lenders',[]):
        world.emit('loan_rejected',loan_id=lid,reason='UNKNOWN_LENDER');return False
    cash=world.economics.cash
    if cash.accounts[lender].available<p:
        world.emit('loan_rejected',loan_id=lid,reason='LENDER_FUNDS');return False
    # Validation precedes one existing-money transfer; principal is never income.
    cash.pay(lender,borrower,p)
    world.loans[lid]=dict(lender=lender,borrower=borrower,principal=p,interest=interest,due_day=due,repaid=0,remaining=p+interest,creditor_carrying_value=p+interest,status='ACTIVE')
    world.emit('loan_issued',loan_id=lid,**world.loans[lid])
    return True

def repay(world,lid,event_id,amount):
    q=integer(amount,1);loan=world.loans[lid]
    if q>loan['remaining']:raise ValueError('repayment beyond legal debt')
    world.transfer(event_id,loan['borrower'],loan['lender'],q,reason='loan_repayment',loan_id=lid)
    loan['repaid']+=q;loan['remaining']-=q;loan['creditor_carrying_value']=min(loan['creditor_carrying_value'],loan['remaining'])
    if not loan['remaining']:loan['status']='SETTLED'

def settle(world):
    cfg=world.case.get('credit',{})
    for spec in cfg.get('agreements',[]):
        if spec['issue_day']==world.day:issue(world,spec)
    for lid,loan in sorted(world.loans.items()):
        world.metrics['active_debt_visits']+=int(loan['remaining']>0)
        if world.day<loan['due_day'] or not loan['remaining']:continue
        amount=min(loan['remaining'],world.economics.cash.accounts[loan['borrower']].available)
        if amount:repay(world,lid,f'repay:{lid}:{world.day}:{loan["remaining"]}',amount)
        if loan['remaining'] and world.day>=loan['due_day']:
            loan['status']='OVERDUE';world.emit('loan_overdue',loan_id=lid,remaining=loan['remaining'])
    for adjustment in cfg.get('adjustments',[]):
        if adjustment['day']!=world.day:continue
        loan=world.loans[adjustment['loan']];q=integer(adjustment['amount'],1)
        if adjustment['kind']=='impair':
            if q>loan['creditor_carrying_value']:raise ValueError('impairment beyond creditor asset')
            loan['creditor_carrying_value']-=q;world.emit('loan_impaired',loan_id=adjustment['loan'],amount=q)
        elif adjustment['kind']=='forgive':
            if q>loan['remaining']:raise ValueError('forgiveness beyond debt')
            loan['remaining']-=q;loan['creditor_carrying_value']=min(loan['creditor_carrying_value'],loan['remaining'])
            if not loan['remaining']:loan['status']='SETTLED'
            world.emit('loan_forgiven',loan_id=adjustment['loan'],amount=q,lender=loan['lender'],borrower=loan['borrower'])
        else:raise ValueError('unknown credit adjustment')
