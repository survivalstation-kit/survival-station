#!/usr/bin/env python3
"""Survival Station - step-by-step USB drive builder (Windows).

Lists the drives, asks a few questions, then runs setup\\build-drive.ps1 for you.
Same steps as MAKE-USB.bat; needs only the Python standard library.

    py make-usb.py
"""
import ctypes
import os
import shutil
import string
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
BUILDER = os.path.join(ROOT, 'setup', 'build-drive.ps1')
SYS = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32')
PS = os.path.join(SYS, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
SYSTEM_DRIVE = os.environ.get('SystemDrive', 'C:').upper()

PRESETS = ['brazil', 'portugal', 'usa', 'alaska', 'hawaii', 'canada', 'canada-south', 'rio-grande-do-sul', 'santa-catarina', 'parana',
           'sao-paulo', 'rio-de-janeiro', 'minas-gerais', 'bahia', 'pernambuco']
REMOVABLE, FIXED = 2, 3


# ---------------------------------------------------------------- drives

def drives():
    """Every removable or fixed drive with media in it, except the system disk."""
    k = ctypes.windll.kernel32
    k.SetErrorMode(1)   # no "insert a disk" pop-ups for empty card readers
    mask = k.GetLogicalDrives()
    found = []
    for i, letter in enumerate(string.ascii_uppercase):
        if not mask >> i & 1:
            continue
        root = letter + ':\\'
        kind = k.GetDriveTypeW(root)
        if kind not in (REMOVABLE, FIXED) or letter + ':' == SYSTEM_DRIVE:
            continue
        free, total = ctypes.c_ulonglong(), ctypes.c_ulonglong()
        if not k.GetDiskFreeSpaceExW(root, ctypes.byref(free), ctypes.byref(total), None):
            continue
        label, fs = ctypes.create_unicode_buffer(261), ctypes.create_unicode_buffer(261)
        k.GetVolumeInformationW(root, label, 261, None, None, None, fs, 261)
        found.append({'drive': letter + ':', 'fs': fs.value or 'RAW', 'free': free.value,
                      'size': total.value, 'usb': kind == REMOVABLE, 'label': label.value})
    return found


def gb(n):
    return f'{n / 1024 ** 3:,.1f} GB'


# ---------------------------------------------------------------- questions

def ask(prompt, choices, default=None):
    """Ask until one of `choices` (single letters/digits) is typed; Enter gives `default`."""
    while True:
        a = input(f'   {prompt} ').strip().upper()[:1]
        if not a and default:
            return default
        if a in choices:
            return a


def pick_drive():
    while True:
        print('\n  Drives on this computer / Unidades neste computador:\n')
        found = drives()
        if found:
            print('     DRIVE  FORMAT        FREE/LIVRE         SIZE  TYPE  NAME')
            for d in found:
                print(f"     {d['drive']}     {d['fs']:<6} {gb(d['free']):>14} {gb(d['size']):>12}  "
                      f"{'USB' if d['usb'] else 'disk':<5} {d['label']}")
        else:
            print('     (none - plug in the USB drive / nenhuma - conecte o pendrive)')
        print(f'     L:    This computer, in a folder / Este computador, numa pasta ({SYSTEM_DRIVE}\\Survival)\n')
        a = input('   Drive letter, L, R to refresh, Enter to go back / Letra, L, R atualiza, Enter volta: ').strip().upper()[:1]
        if not a:
            return None
        if a == 'R':
            continue
        if a == 'L':
            return pick_folder()
        for d in found:
            if d['drive'] == a + ':':
                return d
        if a + ':' == SYSTEM_DRIVE:
            print(f'\n   {SYSTEM_DRIVE} is the system disk. Pick the USB drive. / Escolha o pendrive.')
        else:
            print(f'\n   Drive {a}: not found. / Unidade {a}: nao encontrada.')


def pick_folder():
    """A folder on this computer: runs the same as from the USB drive, and gets a desktop shortcut."""
    default = SYSTEM_DRIVE + '\\Survival'
    path = input(f'   Folder / Pasta [{default}]: ').strip().strip('"').rstrip('\\') or default
    if len(path) <= 2:   # a bare drive letter: use a folder on it
        path = path[:1].upper() + ':\\Survival'
    usage = shutil.disk_usage(path[:3])
    return {'drive': path, 'fs': 'folder', 'free': usage.free, 'size': usage.total, 'usb': False, 'label': ''}


def is_admin():
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except OSError:
        return False


def check_format(d):
    """Offer to format as exFAT. Returns False to go back to the menu."""
    if d['fs'].upper() in ('EXFAT', 'FOLDER'):
        return True
    letter = d['drive'][0]
    print(f"\n   {d['drive']} is formatted as {d['fs']}. The kit needs exFAT: FAT32 can't hold the big\n"
          "   files (over 4 GB), and Macs and phones can't write to NTFS.\n"
          f"   {d['drive']} esta formatado como {d['fs']}. O kit precisa de exFAT.\n\n"
          f"    F  Format {d['drive']} as exFAT now - ERASES EVERYTHING ON IT / APAGA TUDO\n"
          '    C  Continue without formatting / Continuar sem formatar\n'
          '    B  Back / Voltar\n')
    a = ask('[F,C,B]:', 'FCB')
    if a == 'B':
        return False
    if a == 'C':
        return True
    if not is_admin():
        print('\n   Formatting needs administrator rights. / Formatar precisa de administrador.')
        if ask('Restart this as administrator? / Reabrir como administrador? [Y,N]:', 'YN') == 'Y':
            ctypes.windll.shell32.ShellExecuteW(None, 'runas', sys.executable, f'"{os.path.abspath(__file__)}"', ROOT, 1)
            sys.exit(0)
        return False
    if input(f'\n   To ERASE {d["drive"]} type its letter again / Para APAGAR digite a letra de novo: ').strip().upper()[:1] != letter:
        print('   Cancelled, nothing was erased. / Cancelado, nada foi apagado.')
        return False
    print(f"   Formatting {d['drive']} ... / Formatando ...")
    r = subprocess.run([PS, '-NoProfile', '-Command',
                        f"Format-Volume -DriveLetter '{letter}' -FileSystem exFAT -NewFileSystemLabel SURVIVAL "
                        '-Force -Confirm:$false -ErrorAction Stop | Out-Null'])
    if r.returncode:
        print(f"\n   Format failed. Close any windows using {d['drive']} and try again. / Falhou, tente de novo.")
        return False
    print(f"   Done: {d['drive']} is now exFAT. / Pronto: agora e exFAT.")
    return True


def build_args(d):
    print(f"\n  Destination / Destino: {d['drive']}  ({gb(d['free'])} free / livre)\n\n"
          '  How much to put on it? / Quanto colocar?\n'
          '    1  Lite      16 GB drive+  ~9 GB    2 AIs, medicine, water, food, disaster, knots, maps\n'
          '    2  Standard  64 GB drive+  ~33 GB   + smarter AI, Wikipedia, iFixit, more books\n'
          '    3  Full     256 GB drive+  ~139 GB  + full Wikipedia with pictures\n')
    tier = {'1': 'Lite', '2': 'Standard', '3': 'Full'}[ask('[1,2,3]:', '123')]

    print('\n  Library languages / Idiomas da biblioteca:\n'
          '    1  English + Portugues (Brasil)   (Lite +2 GB, Standard +8 GB, Full +20 GB)\n'
          '    2  English only / so ingles\n'
          '    3  Portugues only / so portugues\n')
    langs = {'1': 'en,pt', '2': 'en', '3': 'pt'}[ask('[1,2,3]:', '123')]

    print('\n  Street maps (the world overview is always included) / Mapas de ruas (o mapa-mundi sempre vem):')
    for i, name in enumerate(PRESETS, 1):
        print(f'    {i:>2}  {name}')
    print('  Every street: Brazil 6 GB, USA 17 GB, Canada 16 GB, southern Canada 9 GB, Alaska 0.8 GB.\n'
          '  Pick a country OR its states, not both: Brazil includes every state, Canada includes southern Canada.\n')
    while True:
        sel = input('   Numbers separated by spaces, Enter for none / Numeros separados por espaco, Enter para nenhum: ')
        nums = sel.replace(',', ' ').split()
        if all(n.isdigit() and 1 <= int(n) <= len(PRESETS) for n in nums):
            break
    maps = ','.join(dict.fromkeys(PRESETS[int(n) - 1] for n in nums))

    print('\n  Another area? Draw a box at bboxfinder.com and paste it (minLon,minLat,maxLon,maxLat).\n'
          '  Outra area? Desenhe em bboxfinder.com e cole aqui. Enter to skip / para pular.')
    while True:
        bbox = input('   Box: ').strip().replace(' ', '')
        parts = bbox.split(',')
        try:
            if not bbox or (len(parts) == 4 and [float(p) for p in parts]):
                break
        except ValueError:
            pass
        print('   Needs 4 numbers like -43.8,-23.1,-43.1,-22.7 / Precisa de 4 numeros')
    name = 'custom'
    if bbox:
        name = input('   Name for this map, no spaces / Nome do mapa, sem espacos [custom]: ').strip().replace(' ', '-') or 'custom'

    zoom = '15'
    if maps or bbox:
        print('\n  Map detail / Detalhe do mapa:\n'
              '    1  Every street / Todas as ruas      (zoom 15)\n'
              '    2  Half the size / Metade do tamanho (zoom 14)\n'
              '    3  A quarter / Um quarto             (zoom 13)')
        zoom = {'1': '15', '2': '14', '3': '13'}[ask('[1,2,3]:', '123')]

    gutenberg = ask('\n   Add 70,000 English books from Gutenberg (206 GB)? / Adicionar livros (206 GB)? [N,Y]:', 'NY', 'N') == 'Y'

    args = ['-Drive', d['drive'], '-Tier', tier, '-Languages', langs, '-MapMaxZoom', zoom]
    if maps:
        args += ['-Map', maps]
    if bbox:
        args += ['-MapBbox', bbox, '-MapName', name]
    if gutenberg:
        args += ['-Gutenberg']
    return args


# ---------------------------------------------------------------- actions

def run_builder(args):
    cmd = [PS, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', BUILDER] + args
    print('\n  Running / Executando:\n  powershell -ExecutionPolicy Bypass -File setup\\build-drive.ps1 '
          + subprocess.list2cmdline(args) + '\n')
    return subprocess.run(cmd).returncode


def test_drive(d):
    launcher = os.path.join(d['drive'] + '\\', 'START-WINDOWS.bat')
    if not os.path.exists(launcher):
        print(f"\n   {d['drive']} has no Survival Station on it yet. / ainda nao tem o Survival Station.")
        return
    subprocess.Popen(['cmd', '/c', 'start', 'Survival Station', '/d', d['drive'] + '\\', launcher])
    print(f"\n   Started from {d['drive']} in a new window. Ask the AI something, open the library and the map.\n"
          f"   Iniciado de {d['drive']} em outra janela. Pergunte algo a IA, abra a biblioteca e o mapa.")


def main():
    if os.name != 'nt':
        sys.exit('The drive builder runs on Windows. On Mac/Linux, use the finished drive with START-MAC.command or START-LINUX.sh.')
    if not os.path.exists(BUILDER):
        sys.exit('setup\\build-drive.ps1 not found. Keep this file in the Survival Station folder.')
    os.chdir(ROOT)
    while True:
        print('\n  ==============================================================\n'
              '   SURVIVAL STATION - build the USB drive / montar o pendrive\n'
              '  ==============================================================\n\n'
              '    1  Build or update a drive        / Montar ou atualizar um pendrive\n'
              '    2  Refresh documents + maps list  / Atualizar lista de documentos e mapas\n'
              '    3  Test a finished drive          / Testar um pendrive pronto\n'
              '    4  Update what is on a drive      / Atualizar o que ja esta no pendrive\n'
              '    5  Copy a kit, no internet needed / Copiar um kit, sem internet\n'
              '    6  Verify / repair a drive        / Verificar / reparar um pendrive\n'
              '    R  Resume a stopped build         / Continuar uma montagem parada\n'
              '    Q  Quit                           / Sair\n')
        action = ask('Choose / Escolha [1,2,3,4,5,6,R,Q]:', '123456RQ')
        if action == 'Q':
            return
        if action == '5':
            subprocess.Popen([PS, '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                              '-File', os.path.join(ROOT, 'setup', 'copy-kit.ps1')])
            continue
        d = pick_drive()
        if not d:
            continue
        if action == '3':
            test_drive(d)
        elif action == '2':
            run_builder(['-Drive', d['drive'], '-IndexOnly'])
        elif action == '6':
            run_builder(['-Drive', d['drive'], '-Verify'])
        elif action == 'R':
            print('\n  Building again what BUILD-CHOICES.txt on the drive lists. Finished files are skipped.\n'
                  '  Montando de novo o que o BUILD-CHOICES.txt lista. Arquivos prontos sao pulados.')
            run_builder(['-Drive', d['drive'], '-Resume'])
        elif action == '4':
            print('\n  Newer library editions, AI engine, maps over a year old and Survival-Data.\n'
                  '  Edicoes novas da biblioteca, motor da IA, mapas com mais de um ano e Survival-Data.')
            run_builder(['-Drive', d['drive'], '-Update'])
        elif check_format(d):
            args = build_args(d)
            print('\n  It checks the sizes first and asks before downloading. If the internet drops,\n'
                  '  run this again: it picks up where it stopped.\n'
                  '  Ele confere os tamanhos e pergunta antes de baixar. Se a internet cair,\n'
                  '  rode de novo: ele continua de onde parou.')
            if run_builder(args):
                print('\n   Something went wrong, see above. Run this again to resume.\n'
                      '   Algo deu errado, veja acima. Rode de novo para continuar.')
            elif os.path.exists(os.path.join(d['drive'] + '\\', 'START-WINDOWS.bat')):
                print('\n   Finished. / Pronto.')
                if ask('Test the drive now? / Testar o pendrive agora? [Y,N]:', 'YN') == 'Y':
                    test_drive(d)
        input('\n   Press Enter / Aperte Enter ')


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print()
