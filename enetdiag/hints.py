"""hints - our own short notes for codes we have looked into (not BMW's texts), Polish, for the owner.

hint(address, code) -> {severity, title, what, check} or None. Codes nobody wrote a note for go to the
owner's own AI through the MCP server, with the unit name and status.
severity: 'service' (see a workshop if it stays), 'watch' (clear, see if it returns), 'info' (no fault).
"""
HINTS = {
    (0x12, '101F01'): {
        'severity': 'service',
        'title': 'Masa powietrza w dolocie nieprawdopodobna',
        'what': 'Sterownik silnika liczy inną ilość powietrza niż mierzy. Najczęściej fałszywe powietrze '
                '(odma / pokrywa zaworów, wąż, złączka), rzadziej czujnik.',
        'check': 'Log "analyze": korekty paliwa na wolnych i przy 2500 obr/min. Syczenie przy pokrywie zaworów, '
                 'test korka oleju, złączki dolotu. Warsztat: test dymowy, kasowanie adaptacji po naprawie.',
    },
    (0x37, 'B7F500'): {
        'severity': 'info',
        'title': 'Mikrofon nieskalibrowany',
        'what': 'Moduł audio nie ma kalibracji mikrofonu do rozmów.',
        'check': 'Jeśli rozmówcy słyszą dobrze – zignoruj. Inaczej: kalibracja mikrofonu w ISTA.',
    },
    (0x40, '804070'): {
        'severity': 'watch',
        'title': 'Zasilanie / przekaźnik w module nadwozia',
        'what': 'Zakres kodów zasilania BDC; często po rozładowaniu akumulatora lub długim postoju z zapłonem.',
        'check': 'Skasuj w Fault Scanner. Jeśli wraca – test akumulatora.',
    },
    (0x5D, '800ABF'): {
        'severity': 'info',
        'title': 'Kamera KAFAS: pole widzenia chwilowo ograniczone',
        'what': 'Kamera chwilowo nic nie widziała: brudna szyba, smugi, deszcz, słońce, mróz. To nie usterka.',
        'check': 'Umyj szybę przed kamerą, sprawdź wycieraczki, skasuj.',
    },
}


def hint(address, code):
    return HINTS.get((address, code))
