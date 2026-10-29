#!/usr/bin/env python3
"""Starts a private, GPU-backed GNOME Shell with Xwayland, so runs are not disturbed by your desktop
(notifications, other windows, the compositor of your session). It does not touch your own session.

    tools/display.py start    writes build/display.json, pass it to run.py --display
    tools/display.py stop
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR",f"/run/user/{os.getuid()}")) / "doriax-benchmarks"


def start():
    config = ROOT / "build/display.json"
    config.parent.mkdir(exist_ok=True)
    if config.exists():
        old = json.loads(config.read_text())
        try:
            os.kill(old["session_pid"],0)
            print(config.read_text())
            return
        except ProcessLookupError:
            pass
    RUNTIME.mkdir(mode=0o700,parents=True,exist_ok=True)
    for name in ("config","cache","state","data","services"):
        (RUNTIME/name).mkdir(exist_ok=True)
    bus = RUNTIME / "bus.conf"
    bus.write_text(f'''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><keep_umask/><listen>unix:dir={RUNTIME}</listen>
<auth>EXTERNAL</auth><servicedir>{RUNTIME}/services</servicedir>
<policy context="default"><allow send_destination="*" eavesdrop="true"/>
<allow eavesdrop="true"/><allow own="*"/></policy></busconfig>''')
    env = {k:v for k,v in os.environ.items() if k not in ("DISPLAY","WAYLAND_DISPLAY","DBUS_SESSION_BUS_ADDRESS")}
    env.update(XDG_RUNTIME_DIR=str(RUNTIME),XDG_CONFIG_HOME=str(RUNTIME/"config"),
               XDG_CACHE_HOME=str(RUNTIME/"cache"),XDG_STATE_HOME=str(RUNTIME/"state"),
               XDG_DATA_HOME=str(RUNTIME/"data"),GSETTINGS_BACKEND="memory")
    with (RUNTIME/"shell.log").open("wb") as log:
        p = subprocess.Popen(["dbus-run-session","--config-file="+str(bus),"--",
                              "gnome-shell","--headless","--wayland","--virtual-monitor","1920x1080@60",
                              "--wayland-display","doriax-benchmarks"],env=env,cwd=RUNTIME,
                              stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True)
    for _ in range(150):
        auth = list(RUNTIME.glob(".mutter-Xwaylandauth.*"))
        match=re.search(r"Using public X11 display (:\d+)",(RUNTIME/"shell.log").read_text())
        if auth and match and Path("/tmp/.X11-unix/X"+match[1][1:]).exists():
            info = dict(DISPLAY=match[1],XAUTHORITY=str(auth[0]),session_pid=p.pid)
            config.write_text(json.dumps(info,indent=2)+"\n")
            print(config.read_text())
            return
        if p.poll() is not None: break
        time.sleep(.1)
    os.killpg(p.pid,signal.SIGTERM)
    raise RuntimeError("Display failed; inspect " + str(RUNTIME/"shell.log"))


def stop():
    config = ROOT / "build/display.json"
    if not config.exists(): return
    info = json.loads(config.read_text())
    # Stop only the private session whose command and configuration we own.
    proc = Path(f"/proc/{info['session_pid']}/cmdline")
    if proc.exists() and str(RUNTIME/"bus.conf").encode() in proc.read_bytes():
        os.killpg(info["session_pid"],signal.SIGTERM)
    config.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action",choices=["start","stop"])
    args=parser.parse_args()
    start() if args.action == "start" else stop()
