"""Lets AdGuard's converter build on Linux.

One call in it is Apple's only (an app group's shared folder, used by apps
that load its filter engine; the command-line converter never reaches it):
on Linux it stands for "no such folder".
"""
import sys

path = sys.argv[1] + "/Sources/FilterEngine/WebExtension.swift"
source = open(path, encoding="utf-8").read()
call = ("FileManager.default.containerURL(\n"
        "                forSecurityApplicationGroupIdentifier: groupID\n"
        "            )")
if source.count(call) != 1:
    sys.exit(f"patch-converter: the call moved in {path}; look again for this version")
open(path, "w", encoding="utf-8").write(source.replace(call, "(nil as URL?)"))
print("patch-converter: app group folder call taken out for Linux")
