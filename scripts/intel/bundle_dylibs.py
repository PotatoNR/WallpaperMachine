#!/usr/bin/env python3
"""Copy the non-system dylibs an app binary needs into Contents/Frameworks
and rewrite their install names so the bundle is self-contained."""
import os, subprocess, sys, shutil

APP = sys.argv[1]
CONDA = os.path.abspath(sys.argv[2])
FW = os.path.join(APP, "Contents", "Frameworks")
KEEP_SYSTEM = {"libc++.1.dylib", "libc++abi.1.dylib", "libiconv.2.dylib",
               "libSystem.B.dylib", "libobjc.A.dylib"}

def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout.splitlines()[1:]
    return [l.strip().split(" (compat")[0] for l in out if l.strip()]

def resolve(ref, loader):
    if ref.startswith("@rpath/"):
        cand = os.path.join(CONDA, "lib", ref[len("@rpath/"):])
        return cand if os.path.exists(cand) else None
    if ref.startswith("@loader_path/"):
        cand = os.path.join(os.path.dirname(loader), ref[len("@loader_path/"):])
        return cand if os.path.exists(cand) else None
    if ref.startswith("/"):
        # Third-party dylibs can be recorded with any absolute path (a build tree
        # reached through a symlink, for example). System libraries stay out: they
        # live under /usr/lib or /System and are never vendored.
        if os.path.exists(ref) and not ref.startswith(("/usr/lib/", "/System/")):
            return ref
    return None

roots = [os.path.join(APP, "Contents/MacOS/WallpaperMachine"),
         os.path.join(APP, "Contents/Extensions/WallpaperMachineExtension.appex/Contents/MacOS/WallpaperMachineExtension"),
         os.path.join(APP, "Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter")]
queue, seen = [], {}
for r in roots:
    for d in deps(r):
        p = resolve(d, r)
        if p: queue.append(p)
while queue:
    p = queue.pop()
    name = os.path.basename(p)
    if name in seen or name in KEEP_SYSTEM or name.startswith("libSystem") or name.startswith("libobjc"):
        continue
    seen[name] = p
    for d in deps(p)[1:] if False else deps(p):
        q = resolve(d, p)
        if q and os.path.basename(q) not in seen:
            queue.append(q)

os.makedirs(FW, exist_ok=True)
for name, src in sorted(seen.items()):
    dst = os.path.join(FW, name)
    if not os.path.exists(dst):
        shutil.copy2(src, dst)
    subprocess.run(["install_name_tool", "-id", f"@rpath/{name}", dst], check=True)
    for d in deps(dst):
        base = os.path.basename(d)
        if base in seen or base in KEEP_SYSTEM:
            new = f"@rpath/{base}"
            if d != new:
                subprocess.run(["install_name_tool", "-change", d, new, dst], check=True)

for r in roots:
    for d in deps(r):
        base = os.path.basename(d)
        if base in seen or base in KEEP_SYSTEM:
            new = f"@rpath/{base}"
            if d != new:
                subprocess.run(["install_name_tool", "-change", d, new, r], check=True)
print(f"bundled {len(seen)} dylibs")
for n in sorted(seen): print("  ", n)
