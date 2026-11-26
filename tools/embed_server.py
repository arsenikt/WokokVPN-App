"""Embeds server/box.sh into Dart so the app and the CLI can upload it."""
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
script = (root / 'server' / 'box.sh').read_text(encoding='utf-8')
assert "'''" not in script, "box.sh must not contain triple quotes"
out = root / 'lib' / 'box' / 'server_script.dart'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(
    "// GENERATED from server/box.sh by tools/embed_server.py. Do not edit.\n"
    "const String boxServerScript = r'''\n" + script + "''';\n",
    encoding='utf-8', newline='\n')
print('written', out)
