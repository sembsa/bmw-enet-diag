"""analyze - a log of snapshots -> what it says about 101F01 (air mass plausibility). Pure: no I/O.

analyze(rows) -> report dict; render(report) -> Polish text for the owner.

Reasoning (petrol, closed loop, warm engine):
- false air after the meter: the unit sees more oxygen than it measured, adds fuel -> total trim
  (STFT + LTFT) high at idle, where the leak is a large share of the air, and falling with load.
- meter under-reading (or fuel delivery short): trim high everywhere.
- with an air mass meter: its g/s against a speed-density estimate from MAP, rpm and intake
  temperature; the ratio drifting with load points at the meter rather than a leak.
"""
DISPLACEMENT_L = 1.499          # B38A15
R_AIR = 287.05
VE_GUESS = 0.85                 # shortcut: one volumetric efficiency for all loads; a ratio between bins, not an absolute

WARM_C = 70
TRIM_HIGH = 8.0                 # % total trim worth a look
LEAK_DROP = 5.0                 # % fall from idle to 2500 rpm that marks a leak


def _mean(xs):
    xs = [x for x in xs if x is not None]
    return round(sum(xs) / len(xs), 2) if xs else None


def _sd_airflow(r):
    """Speed-density air mass in g/s from MAP, rpm and intake temperature (4-stroke)."""
    if r.get('map') is None or r.get('rpm') is None or r.get('iat') is None:
        return None
    rho = r['map'] * 1000 / (R_AIR * (r['iat'] + 273.15))          # kg/m3
    return rho * DISPLACEMENT_L / 1000 * VE_GUESS * r['rpm'] / 120 * 1000


def _bin(r):
    rpm = r.get('rpm') or 0
    if 500 < rpm < 1000 and (r.get('speed') or 0) == 0:
        return 'idle'
    if 2200 <= rpm <= 3200:
        return 'mid'
    return None


def analyze(rows):
    warm = [r for r in rows if (r.get('coolant') or 0) >= WARM_C]
    rep = {'rows': len(rows), 'warm_rows': len(warm), 'has_maf': any((r.get('maf') or 0) > 0 for r in rows),
           'bins': {}, 'verdict': None, 'notes': []}
    if not warm:
        rep['verdict'] = 'not_warm'
        return rep
    for name in ('idle', 'mid'):
        rs = [r for r in warm if _bin(r) == name]
        b = {'n': len(rs), 'rpm': _mean([r.get('rpm') for r in rs]),
             'stft': _mean([r.get('stft') for r in rs]), 'ltft': _mean([r.get('ltft') for r in rs]),
             'map': _mean([r.get('map') for r in rs]), 'maf': _mean([r.get('maf') for r in rs])}
        b['trim'] = round(b['stft'] + b['ltft'], 2) if b['stft'] is not None and b['ltft'] is not None else None
        if rep['has_maf']:
            ratios = [r['maf'] / sd for r in rs if r.get('maf') and (sd := _sd_airflow(r))]
            b['maf_vs_model'] = _mean(ratios)
        rep['bins'][name] = b
    idle, mid = rep['bins']['idle'], rep['bins']['mid']
    if idle['n'] < 20:
        rep['notes'].append('few_idle')
    if mid['n'] < 20:
        rep['notes'].append('few_mid')
    if idle['trim'] is None:
        rep['verdict'] = 'no_trims'
        return rep
    hi_idle = idle['trim'] >= TRIM_HIGH
    if mid['trim'] is not None and hi_idle and idle['trim'] - mid['trim'] >= LEAK_DROP:
        rep['verdict'] = 'leak'
    elif hi_idle and (mid['trim'] is None or mid['trim'] >= TRIM_HIGH):
        rep['verdict'] = 'lean_everywhere' if mid['trim'] is not None else 'lean_idle'
    elif idle['trim'] <= -TRIM_HIGH or (mid['trim'] or 0) <= -TRIM_HIGH:
        rep['verdict'] = 'rich'
    else:
        rep['verdict'] = 'trims_normal'
    if rep['has_maf'] and idle.get('maf_vs_model') and mid.get('maf_vs_model'):
        drift = mid['maf_vs_model'] / idle['maf_vs_model']
        rep['maf_drift'] = round(drift, 2)
        if abs(drift - 1) > 0.2:
            rep['notes'].append('maf_drift')
    return rep


TEXT = {
    'not_warm': 'Silnik nie był rozgrzany (płyn < 70 °C) – nagraj log po rozgrzaniu.',
    'no_trims': 'Brak korekt paliwa w logu (sterownik nie podał PID 06/07) – analiza niemożliwa.',
    'leak': 'Korekty wysokie na wolnych i spadają przy 2500 obr/min: typowy obraz NIESZCZELNOŚCI '
            '(fałszywe powietrze: odma / pokrywa zaworów, wąż, złączka).',
    'lean_everywhere': 'Korekty wysokie w całym zakresie: raczej czujnik powietrza zaniża albo brakuje paliwa '
                       '(ciśnienie, wtryski) – mniej typowe dla nieszczelności.',
    'lean_idle': 'Korekty wysokie na wolnych; brak danych z 2500 obr/min, żeby odróżnić nieszczelność od czujnika.',
    'rich': 'Korekty mocno ujemne: silnik dostaje za dużo paliwa / mniej powietrza niż liczy (zawieszony wtrysk, '
            'zapchany filtr, czujnik zawyża).',
    'trims_normal': 'Korekty w normie – w tym logu nie widać fałszywego powietrza. Błąd może zależeć od warunków '
                    '(zimny start, mocne przyspieszenie): sprawdź snapshot błędu.',
}
NOTES = {
    'few_idle': 'Mało próbek na wolnych (< 20): postój 2–3 min na ciepłym silniku.',
    'few_mid': 'Mało próbek przy 2200–3200 obr/min: na postoju przytrzymaj ~2500 obr/min przez 1 min.',
    'maf_drift': 'Stosunek przepływomierza do modelu zmienia się z obrotami o > 20 % – podejrzany przepływomierz.',
}


def render(rep):
    out = ['Próbek: %d (rozgrzany silnik: %d). Przepływomierz (PID 10): %s.'
           % (rep['rows'], rep['warm_rows'], 'jest' if rep['has_maf'] else 'BRAK / zero')]
    for name, label in (('idle', 'Wolne obroty'), ('mid', '2200–3200 obr/min')):
        b = rep['bins'].get(name)
        if b and b['n']:
            out.append('%s: n=%d, rpm %s, STFT %s %%, LTFT %s %%, razem %s %%, MAP %s kPa%s'
                       % (label, b['n'], b['rpm'], b['stft'], b['ltft'], b['trim'], b['map'],
                          ', MAF %s g/s' % b['maf'] if b.get('maf') else ''))
    out.append('Wniosek: ' + TEXT[rep['verdict']])
    out += ['Uwaga: ' + NOTES[n] for n in rep['notes']]
    return '\n'.join(out)
