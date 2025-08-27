#!/usr/bin/env python3
import os
import runpy
import sys
from os.path import join
from pathlib import Path

install_dir = Path(__file__).resolve().parent
vendor = join(install_dir, "vendor")
if vendor.exists():
    sys.path.insert(0, str(vendor))
sys.path.insert(0, str(install_dir))
cands = [
    join(install_dir, "granturismo", "proxy.py"),
    join(install_dir, "granturismo", "scripts", "proxy.py"),
]
t = next((p for p in cands if p.exists()), None)
if t is None:
    sys.stderr.write("proxy-wrapper.py: could not find granturismo proxy.py\n")
    sys.exit(1)
os.chdir(str(install_dir))
sys.argv = ["proxy.py"] + sys.argv[1:]
runpy.run_path(str(t), run_name="__main__")
