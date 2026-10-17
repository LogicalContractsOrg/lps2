#!/usr/bin/env python3
"""Write the scenario "the demo record" of trade_lifecycle_record.le from the
files of ex-cdm-swaps kept in sources/ (examples/NewTrade, examples/TradeEvents).

Each event is dated by its own event date. One party (the first the file
names) proposes it; the other parties accept it the same day, as the
example's DemoBot does, except the three acceptances its docs/demo.md has
made by hand, which come on a later day; the ledger applies a new trade once
every party has accepted it, and a later event on its effective date.
Each day that has something happen takes three cycles: the day begins,
the proposals, the acceptances; the ledger applies in the cycle after the
acceptances, which is also the cycle in which the next day begins, and so
still reads the day it applies on.

    python3 build.py        (rewrites the end of trade_lifecycle_record.le)
"""
import collections, datetime, glob, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'sources', 'examples')
LE = os.path.join(HERE, 'trade_lifecycle_record.le')
MARK = '% --- the demo record (written by build.py from sources/; do not edit) ---'

# docs/demo.md: "The DemoBot auto-accepts all events except two", and the
# same for the trade events. Those acceptances are made the next day of
# the record.
BY_HAND = {('CAXMKVEHOV', 'CCP_P01'), ('QZPRYFPGA1', 'CLIENT_C04'),
           ('XJKUGGSW2D', 'CLIENT_C03'), ('AFD58TK6B1R', 'CLIENT_C03'),
           ('AFD58TK6B1R', 'DEALER_D03')}

def name(p): return p.replace('-', '_')
def amount(x): return ('%d' % x) if float(x) == int(x) else repr(x)

trades = {}                                # rosettaKey -> (id, notional)
acts = collections.defaultdict(lambda: collections.defaultdict(list))   # date -> stage -> lines

for f in sorted(glob.glob(os.path.join(SRC, 'NewTrade', '*.json'))):
    a = json.load(open(f))['argument']
    c = a['after']['contract']
    cid = c['contractIdentifier'][0]['assignedIdentifier'][0]['identifier']['value']
    pay = c['contractualProduct']['economicTerms']['payout']
    n = pay['interestRatePayout'][0]['quantity']['notionalSchedule']['notionalStepSchedule']['initialValue']
    trades[c['rosettaKey']] = (cid, n)
    ps = [name(p['p']) for p in a['ps']]
    d = a['base']['eventDate']
    acts[d]['propose'].append('%s proposes the new trade %s with %s for %s' % (ps[0], cid, ps[1], amount(n)))
    late = [p for p in ps[1:] if (cid, p) in BY_HAND]
    for p in ps[1:]:
        if p not in late: acts[d]['accept'].append('%s accepts %s' % (p, cid))
    when = d
    if late:
        when = (datetime.date.fromisoformat(d) + datetime.timedelta(days=1)).isoformat()
        for p in late: acts[when]['accept'].append('%s accepts %s' % (p, cid))
    acts[when]['apply'].append('the ledger applies %s' % cid)

for f in sorted(glob.glob(os.path.join(SRC, 'TradeEvents', '*.json'))):
    d = json.load(open(f)); a = d['argument']; b = a['base']
    eid = b['eventIdentifier'][0]['assignedIdentifier'][0]['identifier']['value']
    cid, n = trades[a['contractReference']]
    ps = [name(p['p']) for p in a['ps']]
    ev, eff = b['eventDate'], b['effectiveDate']
    change = [c['notionalSchedule']['notionalStepSchedule']['initialValue'] for c in a.get('change', [])]
    choice = d['choice']
    if choice == 'ProposeTermination':
        line = '%s proposes %s to terminate %s effective on %s' % (ps[0], eid, cid, eff)
    elif choice == 'ProposePartialTermination':
        line = '%s proposes %s to terminate %s of %s effective on %s' % (ps[0], eid, amount(change[0]), cid, eff)
    else:
        new = a['contractNew']
        newid = new['contractIdentifier'][0]['assignedIdentifier'][0]['identifier']['value']
        newparties = [name(p['name']['value']) for p in new['party']]
        moved = change[0] if change else n          # a full novation moves it all
        acts[ev]['_novation'].append((ps, eid, cid, moved, newid, newparties, eff))
        continue
    acts[ev]['propose'].append(line)
    for p in ps[1:]:
        acts[ev]['accept'].append('%s accepts %s' % (p, eid))
    acts[eff]['apply'].append('the ledger applies %s' % eid)

# A novation names the party that arrives (in the event, not in the old
# trade), the party that stays (in both trades) and the party that leaves.
holders = {}
for f in sorted(glob.glob(os.path.join(SRC, 'NewTrade', '*.json'))):
    a = json.load(open(f))['argument']; c = a['after']['contract']
    holders[c['contractIdentifier'][0]['assignedIdentifier'][0]['identifier']['value']] = [name(p['name']['value']) for p in c['party']]
for d in list(acts):
    for ps, eid, cid, moved, newid, newparties, eff in acts[d].pop('_novation', []):
        old = holders[cid]
        transferee = [p for p in ps if p not in old][0]
        stays = [p for p in newparties if p in old][0]
        transferor = [p for p in old if p != stays][0]
        acts[d]['propose'].append('%s proposes %s to novate %s of %s from %s to %s as %s effective on %s'
                                  % (ps[0], eid, amount(moved), cid, transferor, transferee, newid, eff))
        for p in ps[1:]:
            acts[d]['accept'].append('%s accepts %s' % (p, eid))
        acts[eff]['apply'].append('the ledger applies %s' % eid)

lines, t = [], 1
for d in sorted(acts):
    lines.append('    the day %s begins from %d to %d.' % (d, t, t + 1))
    for stage, at in (('propose', t + 1), ('accept', t + 2), ('apply', t + 3)):
        for l in acts[d].get(stage, []):
            lines.append('    %s from %d to %d.' % (l, at, at + 1))
    t += 3
text = open(LE).read().split(MARK)[0]
scen = ('%s\n\n%% %d days, %d new trades, %d later events. It breaks no rule.\n'
        'scenario the demo record is:\n%s\n') % (MARK, len(acts), len(trades),
        len(glob.glob(os.path.join(SRC, 'TradeEvents', '*.json'))), '\n'.join(lines))
open(LE, 'w').write(text + scen)
print('days', len(acts), 'last cycle', t)
