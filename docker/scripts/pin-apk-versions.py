#!/usr/bin/env python3
"""
pin-apk-versions.py — Épingle ET met à jour les versions APK dans un Dockerfile multi-stage.

Stratégie : télécharge l'APKINDEX.tar.gz depuis le CDN Alpine (main + community),
le parse en mémoire. Aucun Docker requis, aucune API tierce.

Modes :
  - Premier lancement  : épingle tous les paquets non versionnés
  - Mise à jour        : met à jour les paquets déjà épinglés (--update)
  - Les deux           : --update (comportement par défaut si tout est déjà épinglé)

Usage:
    python3 pin-apk-versions.py [OPTIONS] <Dockerfile>

Options:
    --alpine-version VERSION   Version Alpine (défaut: détectée depuis le Dockerfile)
    --update                   Met à jour les versions déjà épinglées
    --dry-run                  Affiche le diff sans modifier le fichier
    --output FILE              Fichier de sortie (défaut: modification en place)
    --no-backup                Ne crée pas de fichier .bak
    --arch ARCH                Architecture (défaut: x86_64)

Exemples:
    python3 pin-apk-versions.py docker/Dockerfile
    python3 pin-apk-versions.py --update docker/Dockerfile
    python3 pin-apk-versions.py --update --dry-run docker/Dockerfile
"""

import argparse
import io
import re
import sys
import tarfile
import urllib.request
from pathlib import Path
from typing import Optional


# ─────────────────────────────────────────────────────────────────────────────
# Téléchargement et parsing de l'APKINDEX
# ─────────────────────────────────────────────────────────────────────────────

CDN    = "https://dl-cdn.alpinelinux.org/alpine"
REPOS  = ["main", "community"]


def download_apkindex(alpine_version: str, repo: str, arch: str) -> bytes:
    branch = f"v{alpine_version.lstrip('v')}"
    url    = f"{CDN}/{branch}/{repo}/{arch}/APKINDEX.tar.gz"
    print(f"  📥 {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "pin-apk-versions/3.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def parse_apkindex(raw_gz: bytes) -> dict:
    """
    Parse un APKINDEX.tar.gz → {pkg_name: version}.
    Format : blocs séparés par ligne vide, P: = nom, V: = version.
    """
    packages = {}
    with tarfile.open(fileobj=io.BytesIO(raw_gz), mode="r:gz") as tar:
        try:
            member = tar.getmember("APKINDEX")
        except KeyError:
            return packages
        content = tar.extractfile(member).read().decode("utf-8", errors="replace")

    current_name = current_version = None
    for line in content.splitlines():
        line = line.strip()
        if not line:
            if current_name and current_version and current_name not in packages:
                packages[current_name] = current_version
            current_name = current_version = None
        elif line.startswith("P:"):
            current_name = line[2:]
        elif line.startswith("V:"):
            current_version = line[2:]

    if current_name and current_version and current_name not in packages:
        packages[current_name] = current_version

    return packages


def build_version_db(alpine_version: str, arch: str = "x86_64") -> dict:
    """Construit la DB complète : main + community (main a priorité)."""
    db = {}
    for repo in REPOS:
        try:
            raw      = download_apkindex(alpine_version, repo, arch)
            repo_db  = parse_apkindex(raw)
            added    = 0
            for name, version in repo_db.items():
                if name not in db:
                    db[name] = version
                    added += 1
            print(f"  ✅ {repo:12s} → {len(repo_db)} paquets ({added} nouveaux)")
        except Exception as e:
            print(f"  ⚠️  {repo:12s} → erreur : {e}")
    return db


# ─────────────────────────────────────────────────────────────────────────────
# Détection de la version Alpine
# ─────────────────────────────────────────────────────────────────────────────

ALPINE_ARG_RE  = re.compile(r'^ARG\s+ALPINE_VERSION\s*=\s*(\S+)', re.MULTILINE)
FROM_ALPINE_RE = re.compile(r'^FROM\s+alpine:(\S+)',              re.MULTILINE | re.IGNORECASE)


def detect_alpine_version(content: str) -> Optional[str]:
    for pattern in (ALPINE_ARG_RE, FROM_ALPINE_RE):
        m = pattern.search(content)
        if m:
            val = m.group(1).strip()
            if not val.startswith("$"):
                return val
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Parser du Dockerfile
# ─────────────────────────────────────────────────────────────────────────────

SHELL_ONLY = {
    "if","then","else","elif","fi","for","while","until","do","done",
    "case","esac","in","select","function","return","exit","break","continue",
    "set","export","unset","local","declare","readonly","typeset",
    "true","false","source","eval","exec","read","shift",
    "&&","||","|",";","&","(",")","[","]","[[","]]","{","}",
    "apk","add","update","del","fix","upgrade","info","search",
    "cache","fetch","audit","verify","policy",
    "RUN","FROM","ARG","ENV","COPY","ADD","LABEL","EXPOSE",
    "VOLUME","USER","WORKDIR","CMD","ENTRYPOINT","HEALTHCHECK",
    "SHELL","ONBUILD","STOPSIGNAL",
}

PKG_NAME_RE    = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9._+\-]{1,}$')
# Capture le nom ET la version si déjà épinglé : "bash=5.2.26-r0" → ("bash", "5.2.26-r0")
PKG_PINNED_RE  = re.compile(r'^([a-zA-Z0-9][a-zA-Z0-9._+\-]*)=([^\s\\]+)$')
PKG_ANY_PIN_RE = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9._+\-]*[=<>~]')


def clean_line(raw: str) -> str:
    line = re.sub(r'\s*#.*$', '', raw).rstrip()
    if line.endswith("\\"):
        line = line[:-1]
    return line.strip()


def is_valid_pkg_token(token: str) -> bool:
    """Token valide comme nom de paquet (épinglé ou non)."""
    if not token:                                        return False
    if token.startswith("-"):                            return False
    if token.startswith("$") or token.startswith("{"):  return False
    if "/" in token or "\\" in token:                   return False
    if token in SHELL_ONLY:                              return False
    # Accepte pkg seul ET pkg=version
    bare = token.split("=")[0].split(">")[0].split("<")[0].split("~")[0]
    return bool(PKG_NAME_RE.match(bare))


def parse_run_block(lines: list, start: int, include_pinned: bool = False) -> list:
    """
    Parse un bloc RUN multi-lignes.

    Retourne une liste de :
        (line_idx, pkg_name, current_version_or_None)

    Si include_pinned=True  → retourne aussi les paquets déjà épinglés
    Si include_pinned=False → retourne seulement les paquets non épinglés
    """
    block = []
    i = start
    while i < len(lines):
        had_bs = lines[i].rstrip().endswith("\\")
        block.append((i, clean_line(lines[i]), had_bs))
        if had_bs:
            i += 1
        else:
            break

    results = []
    in_apk  = False

    for line_idx, text, _bs in block:
        apk_match = re.search(r'\bapk\s+add\b', text)

        if apk_match:
            in_apk  = True
            segment = text[apk_match.end():]
        elif in_apk:
            segment = text
        else:
            continue

        if segment.lstrip().startswith(("&&", "||", ";")):
            in_apk = False
            continue

        sep_m = re.search(r'\s+(&&|\|\||;)\s*', segment)
        if sep_m:
            segment = segment[:sep_m.start()]
            in_apk  = False

        for token in segment.split():
            token = token.strip()
            if not token:
                continue
            if token in SHELL_ONLY:
                in_apk = False
                break

            # Paquet déjà épinglé : "bash=5.2.26-r0"
            pinned_m = PKG_PINNED_RE.match(token)
            if pinned_m:
                if include_pinned:
                    results.append((line_idx, pinned_m.group(1), pinned_m.group(2)))
                continue

            # Autre opérateur (>=, ~=) → on ignore
            if PKG_ANY_PIN_RE.match(token):
                continue

            # Paquet non épinglé
            if is_valid_pkg_token(token):
                results.append((line_idx, token, None))

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Patch du Dockerfile
# ─────────────────────────────────────────────────────────────────────────────

def pin_package_in_line(line: str, pkg: str, new_version: str,
                        old_version: Optional[str] = None) -> str:
    """
    - Si old_version fourni  → remplace `pkg=old_version` par `pkg=new_version`
    - Sinon                  → remplace le token `pkg` nu par `pkg=new_version`
    Word-boundary strict pour éviter les faux positifs (/bin/bash, gnupg-dirmngr).
    """
    if old_version:
        # Mise à jour d'une version existante
        old_token = re.escape(f"{pkg}={old_version}")
        return re.sub(old_token, f"{pkg}={new_version}", line)
    else:
        # Premier épinglage
        pattern = (
            r'(?:(?<=\s)|(?<=\t)|(?:^))'
            + re.escape(pkg)
            + r'(?=[=<>~\s\\#\n]|$)'
            + r'(?![=<>~])'
        )
        return re.sub(pattern, f"{pkg}={new_version}", line, flags=re.MULTILINE)


def collect_pkg_locations(lines: list, include_pinned: bool) -> list:
    """Parcourt tout le Dockerfile et collecte les (line_idx, pkg, current_ver)."""
    all_locs = []
    visited  = set()
    i = 0
    while i < len(lines):
        if i not in visited and re.search(r'\bapk\s+add\b', lines[i]):
            pkgs = parse_run_block(lines, i, include_pinned=include_pinned)
            all_locs.extend(pkgs)
            j = i
            while j < len(lines):
                visited.add(j)
                if lines[j].rstrip().endswith("\\"):
                    j += 1
                else:
                    break
        i += 1
    return all_locs


def patch_dockerfile(content: str, version_db: dict,
                     update_mode: bool = False,
                     dry_run: bool = False) -> tuple:
    """
    Patche le Dockerfile.
    - update_mode=False : épingle seulement les paquets sans version
    - update_mode=True  : épingle + met à jour les versions existantes
    """
    lines    = content.splitlines(keepends=True)
    all_locs = collect_pkg_locations(lines, include_pinned=update_mode)

    if not all_locs:
        return content, 0, 0

    # Résolution
    unique_pkgs = sorted({pkg for _, pkg, _ in all_locs})
    print(f"\n📌 Résolution de {len(unique_pkgs)} paquet(s) depuis l'index Alpine...")

    resolved  = {}
    not_found = []
    for pkg in unique_pkgs:
        ver = version_db.get(pkg)
        if ver:
            resolved[pkg] = ver
            print(f"  ✅ {pkg:35s} → {ver}")
        else:
            not_found.append(pkg)
            print(f"  ⚠️  {pkg:35s} → non trouvé (community étendu? virtuel?)")

    if not_found:
        print(f"\n  ℹ️  {len(not_found)} paquet(s) non trouvés — non modifiés.")

    # Patch
    new_lines     = list(lines)
    pinned_count  = 0
    updated_count = 0

    for line_idx, pkg, current_ver in all_locs:
        new_ver = resolved.get(pkg)
        if not new_ver:
            continue

        original = new_lines[line_idx]

        if current_ver is None:
            # Premier épinglage
            patched = pin_package_in_line(original, pkg, new_ver, old_version=None)
            if patched != original:
                if dry_run:
                    print(f"  📝 L{line_idx+1} [PIN]    {pkg} → {pkg}={new_ver}")
                new_lines[line_idx] = patched
                pinned_count += 1
        else:
            # Mise à jour
            if current_ver == new_ver:
                print(f"  ✔  L{line_idx+1} [OK]     {pkg}={current_ver} (déjà à jour)")
                continue
            patched = pin_package_in_line(original, pkg, new_ver, old_version=current_ver)
            if patched != original:
                if dry_run:
                    print(f"  📝 L{line_idx+1} [UPDATE] {pkg}: {current_ver} → {new_ver}")
                else:
                    print(f"  🔄 L{line_idx+1} [UPDATE] {pkg}: {current_ver} → {new_ver}")
                new_lines[line_idx] = patched
                updated_count += 1

    return "".join(new_lines), pinned_count, updated_count


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Épingle et met à jour les versions APK dans un Dockerfile Alpine.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("dockerfile",
                        help="Chemin vers le Dockerfile")
    parser.add_argument("--alpine-version", default=None,
                        help="Version Alpine (ex: 3.22). Détectée auto si absent.")
    parser.add_argument("--update", action="store_true",
                        help="Met aussi à jour les versions déjà épinglées")
    parser.add_argument("--dry-run", action="store_true",
                        help="Affiche les changements sans modifier le fichier")
    parser.add_argument("--output", default=None,
                        help="Fichier de sortie (défaut: modification en place)")
    parser.add_argument("--no-backup", action="store_true",
                        help="Ne crée pas de fichier .bak")
    parser.add_argument("--arch", default="x86_64",
                        help="Architecture cible (défaut: x86_64)")
    args = parser.parse_args()

    dockerfile_path = Path(args.dockerfile)
    if not dockerfile_path.exists():
        print(f"❌ Fichier introuvable : {args.dockerfile}", file=sys.stderr)
        sys.exit(1)

    content = dockerfile_path.read_text(encoding="utf-8")

    alpine_version = args.alpine_version or detect_alpine_version(content)
    if not alpine_version or alpine_version.startswith("$"):
        print("❌ Version Alpine non détectée — utilisez --alpine-version X.Y", file=sys.stderr)
        sys.exit(1)

    mode_label = "PIN + UPDATE" if args.update else "PIN uniquement"
    print(f"🐳 Dockerfile  : {dockerfile_path}")
    print(f"🏔  Alpine      : {alpine_version}  arch={args.arch}")
    print(f"⚙️  Mode         : {mode_label}")

    # ── Téléchargement de l'index ──
    print(f"\n📦 Téléchargement de l'index Alpine {alpine_version}...")
    version_db = build_version_db(alpine_version, args.arch)

    if not version_db:
        print("❌ Index Alpine vide — vérifiez votre connexion réseau.", file=sys.stderr)
        sys.exit(1)

    print(f"   → {len(version_db)} paquets dans l'index")

    if args.dry_run:
        print("\n🔎 Mode DRY-RUN — aucun fichier modifié")

    # ── Patch ──
    new_content, pinned, updated = patch_dockerfile(
        content,
        version_db,
        update_mode=args.update,
        dry_run=args.dry_run,
    )

    # ── Résumé ──
    print(f"\n{'─'*50}")
    print(f"  📌 Nouveaux épinglages : {pinned}")
    if args.update:
        print(f"  🔄 Mises à jour        : {updated}")
    print(f"{'─'*50}")

    if args.dry_run:
        sys.exit(0)

    if pinned == 0 and updated == 0:
        print("✅ Dockerfile déjà à jour — aucune modification.")
        sys.exit(0)

    # ── Écriture ──
    output_path = Path(args.output) if args.output else dockerfile_path

    if not args.no_backup and output_path == dockerfile_path:
        backup = dockerfile_path.with_suffix(dockerfile_path.suffix + ".bak")
        backup.write_text(content, encoding="utf-8")
        print(f"💾 Backup : {backup}")

    output_path.write_text(new_content, encoding="utf-8")
    print(f"✅ Dockerfile mis à jour → {output_path}")


if __name__ == "__main__":
    main()