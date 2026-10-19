"""Read-only distribution audit: never treat an entry compile as release acceptance."""
import argparse
import hashlib
import json
from pathlib import Path


def audit(candidate_path, compile_path):
    candidate = json.loads(candidate_path.read_text())
    compile_receipt = json.loads(compile_path.read_text())
    blockers = []
    blocked = []
    for digest, row in candidate['objects'].items():
        if row['state'].startswith('blocked-'):
            blocked.append({'object': digest, 'paths': row['paths'],
                            'state': row['state'], 'reason': row.get('reason', row.get('scope'))})
    if blocked:
        blockers.append('Unresolved executable transformations or ownership scopes')
    if candidate.get('releaseReady') is not True:
        blockers.append('Catalog is explicitly unapproved for release')
    if compile_receipt.get('target') != 'ipa-app-store':
        blockers.append('No App Store distribution compile receipt')
    if compile_receipt.get('compiled') is not True or compile_receipt.get('interpreter') is not False:
        blockers.append('No successful native AOT compilation')
    if compile_receipt.get('runtimeTested') is not True:
        blockers.append('No physical device runtime acceptance')
    if compile_receipt.get('appStoreReady') is not True:
        blockers.append('Build explicitly lacks App Store acceptance')
    return {'ready': not blockers, 'blockers': blockers,
            'candidateSha256': hashlib.sha256(candidate_path.read_bytes()).hexdigest(),
            'compileReceiptSha256': hashlib.sha256(compile_path.read_bytes()).hexdigest(),
            'catalogCounts': candidate['counts'], 'blockedObjects': blocked,
            'compiledContentFiles': compile_receipt.get('compiledContentFiles'),
            'note': 'Readiness evidence only; no binaries, assets, server or device changed.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--compile-receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.candidate, args.compile_receipt)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('ready', 'blockers', 'catalogCounts', 'compiledContentFiles')}, indent=2))
    raise SystemExit(0 if report['ready'] else 1)


if __name__ == '__main__':
    main()
