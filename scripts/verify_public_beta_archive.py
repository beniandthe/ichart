#!/usr/bin/env python3
"""Read-only public-beta source/archive/export guard. Never builds or uploads."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shlex
import stat
import struct
import subprocess
import sys
import tempfile
from zipfile import ZipFile

BUNDLE_ID = 'com.ichart.app'
TEAM = 'N6G8X4K46U'
VERSION = '1.9.4'
BUILD = '174'
PRODUCTION_URL = 'https://pausvvwoazbvmzyrebwl.supabase.co'
PRODUCTION_KEY_SHA256 = 'f18ceef124ea533fd0f738afd352dd5fec4dc8776bb2e5139449996d805e7b7d'
FORBIDDEN_FLAGS = {'DEBUG', 'ICHART_PAID_SUBSCRIPTION', 'ICHART_STAGING_STOREKIT_PRODUCTS',
                   'ICHART_LOCAL_PLAN_QA', 'ICHART_LOCAL_QA_PLAN_PREVIEW'}
XCODE_SWIFT_WRAPPERS = {'builtin-SwiftDriver', 'builtin-Swift-Compilation-Requirements',
                        'builtin-Swift-Compilation'}
ACTIVE_ENTITLEMENTS = {'application-identifier': TEAM + '.' + BUNDLE_ID,
                       'com.apple.developer.team-identifier': TEAM,
                       'beta-reports-active': True, 'get-task-allow': False}
REQUIRED_SOURCES = ('iChart/Models/IChartProductAccessPolicy.swift',
                    'iChart/Models/IChartStoreKitProductCatalog.swift',
                    'iChart/Persistence/IChartStorageNamespace.swift')
PARKED_MARKERS = ('personalmlcomparison', 'personalvisualencoderresearch', 'private-profile.json',
                  'myscript', 'neuralink', 'recognizergraph', '.mlmodel', '.mlpackage', '.onnx', '.tflite')


class GuardError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise GuardError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def run(*command):
    result = subprocess.run(command, capture_output=True)
    require(result.returncode == 0, 'Required verification command failed: ' + Path(command[0]).name)
    return result


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as stream:
        os.chmod(path, 0o600)
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def source_contracts(source):
    policy = (source / REQUIRED_SOURCES[0]).read_text()
    namespace = (source / REQUIRED_SOURCES[2]).read_text()
    catalog = (source / REQUIRED_SOURCES[1]).read_text()
    require(re.search(r'#if ICHART_PAID_SUBSCRIPTION\s+static let current: Self = \.paidSubscription\s+#else\s+static let current: Self = \.freeAllFeatures\s+#endif', policy),
            'Public product policy branch changed; review the free-beta contract.')
    require(re.search(r'#if ICHART_STAGING_STOREKIT_PRODUCTS\s+static let mode: Mode = \.internalStaging\s+#else\s+static let mode: Mode = \.publicApp\s+#endif', namespace),
            'Public storage namespace branch changed; review original-data routing.')
    require(re.search(r'case \.publicApp:\s*\n\s*return \.standard\s*\n\s*case \.internalStaging:', namespace) and
            re.search(r'case \.publicApp:\s*\n\s*return root\s*\n\s*case \.internalStaging:', namespace) and
            re.search(r'^\s*mode == \.internalStaging \? stagingAuthKeyPrefix \+ key : key\s*$', namespace, re.M),
            'Public preferences, files or auth-key compatibility changed.')
    branch = re.search(r'#if ICHART_STAGING_STOREKIT_PRODUCTS\s*\n.*?#else\s*\n(.*?)#endif', catalog, re.S)
    require(branch is not None and all('"' + item + '"' in branch.group(1) for item in
            ('com.ichart.app.pro.monthly', 'com.ichart.app.pro.annual')),
            'Normal StoreKit product catalog changed.')
    return {'policy': 'freeAllFeatures', 'namespace': 'publicApp', 'authKeys': 'unchanged',
            'storeKitProducts': ['com.ichart.app.pro.monthly', 'com.ichart.app.pro.annual']}


def snapshot_source(source):
    git = lambda *args: run('git', '--no-optional-locks', '-C', str(source), *args).stdout
    require(not git('status', '--porcelain=v1', '--untracked-files=all'), 'Source must be committed and clean before pin/verification.')
    tracked = [p.decode() for p in git('ls-files', '-z').split(b'\0') if p]
    names = {p for p in tracked if p in {'project.yml', 'Package.swift'} or
             p.startswith(('iChart/', 'ThirdParty/', 'StoreKit/', 'scripts/'))}
    names.update({'iChart.xcodeproj/project.pbxproj',
                  'iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'})
    files = {}
    for name in sorted(names):
        path = source / name
        require(path.is_file() and not path.is_symlink(), 'Missing or nonregular build input.')
        files[name] = sha(path.read_bytes())
    return {'head': git('rev-parse', 'HEAD').decode().strip(),
            'tree': git('rev-parse', 'HEAD^{tree}').decode().strip(), 'files': files,
            'contracts': source_contracts(source)}


def expand_responses(tokens, derived, depth=0):
    require(depth < 6, 'Compiler response files nested too deeply.')
    result = []
    for token in tokens:
        if token.startswith('@'):
            path = Path(token[1:]).resolve()
            require(path.is_relative_to(derived.resolve()) and path.is_file() and not path.is_symlink()
                    and path.stat().st_size <= 4 * 1024 * 1024, 'Compiler response file outside this build or unavailable.')
            result.extend(expand_responses(shlex.split(path.read_text()), derived, depth + 1))
        else:
            result.append(token)
    return result


def compiler_evidence(log_text, derived_data, source=None):
    """Accept Xcode's real driver format, never echo/build-setting text.

    Wrapper/response-file checks follow the tested internal packager parser;
    this independent public guard rejects every paid/staging/preview define.
    """
    derived = Path(derived_data).resolve()
    commands = []
    for line in log_text.splitlines():
        if 'swiftc' not in line or '-module-name' not in line:
            continue
        tokens = shlex.split(line)
        if '-module-name' not in tokens:
            continue
        index = tokens.index('-module-name')
        if index + 1 >= len(tokens) or tokens[index + 1] != 'iChart':
            continue
        wrapper = tokens[0] if len(tokens) > 2 and tokens[0] in XCODE_SWIFT_WRAPPERS and tokens[1] == '--' else None
        start = 2 if wrapper else 0
        require(len(tokens) > start and Path(tokens[start]).is_absolute() and Path(tokens[start]).name == 'swiftc'
                and '/Contents/Developer/Toolchains/' in tokens[start], 'App evidence must start with the actual Xcode Swift driver.')
        tokens = expand_responses(tokens, derived)
        require('-target' in tokens and tokens.index('-target') + 1 < len(tokens), 'App compiler target missing.')
        target = tokens[tokens.index('-target') + 1]
        require(re.fullmatch(r'arm64(?:e)?-apple-ios[0-9.]+', target), 'App compiler must target native arm64 iOS.')
        require('-Onone' not in tokens and any(p in tokens for p in ('-O', '-Osize', '-Ounchecked')), 'App compiler must be optimized Release.')
        conditions = set()
        i = 0
        while i < len(tokens):
            token = tokens[i]
            if token in {'-Xcc', '-Xllvm', '-Xlinker', '-Xfrontend'}:
                require(i + 1 < len(tokens), 'Incomplete forwarded compiler argument.')
                require(token != '-Xfrontend' or not tokens[i + 1].startswith('-D'), 'Forwarded Swift conditions are unsupported.')
                i += 2
                continue
            if token == '-D':
                require(i + 1 < len(tokens), 'Incomplete Swift condition.')
                conditions.add(tokens[i + 1])
                i += 2
                continue
            if token.startswith('-D') and len(token) > 2:
                conditions.add(token[2:])
            i += 1
        require(not {p.split('=', 1)[0] for p in conditions}.intersection(FORBIDDEN_FLAGS), 'App compiler contains a forbidden paid, staging, Debug or preview condition.')
        map_receipt = None
        if source is not None:
            require('-output-file-map' in tokens and tokens.index('-output-file-map') + 1 < len(tokens), 'App compiler output map missing.')
            path = Path(tokens[tokens.index('-output-file-map') + 1]).resolve()
            require(path.is_relative_to(derived) and path.is_file(), 'App compiler output map outside this build.')
            mapping = json.loads(path.read_text())
            require({(source / p).resolve() for p in REQUIRED_SOURCES} <= {Path(p).resolve() for p in mapping if p}, 'App compiler not bound to current policy, catalog and namespace.')
            map_receipt = {'path': str(path.relative_to(derived)), 'sha256': sha(path.read_bytes())}
        commands.append({'wrapper': wrapper or 'direct-swiftc', 'conditions': sorted(conditions),
                         'command_sha256': sha(line.encode()), 'output_file_map': map_receipt})
    require(commands and any(p['wrapper'] != 'builtin-Swift-Compilation-Requirements' for p in commands),
            'No actual iChart driver/compilation; requirements-only/build-setting evidence is insufficient.')
    return commands


def build_metadata(source, derived, pin_time):
    result = []
    for path in derived.rglob('build-request.json'):
        if not path.parent.name.endswith('.xcbuilddata'):
            continue
        request = json.loads(path.read_text())
        if Path(request.get('containerPath', '')).resolve() != (source / 'iChart.xcodeproj').resolve():
            continue
        require(path.stat().st_mtime >= pin_time, 'Archive request predates source pin.')
        params = request.get('parameters', {})
        require(request.get('useDryRun') is False and params.get('configurationName') == 'Release'
                and request.get('schemeCommand') == 'archive' and params.get('action') in {'install', 'archive'}
                and params.get('activeRunDestination', {}).get('platform') == 'iphoneos', 'Not a native Release archive request.')
        manifest_path = path.with_name('manifest.json')
        manifest = json.loads(manifest_path.read_text())
        matched = []
        for name, command in manifest.get('commands', {}).items():
            if command.get('tool') != 'swift-driver-compilation' or not re.fullmatch(
                    r'SwiftDriver Compilation iChart normal arm64(?:e)? com\.apple\.xcode\.tools\.swift\.compiler', command.get('description', '')):
                continue
            require(':Release:SwiftDriver Compilation iChart normal ' in name, 'App compiler manifest is not Release.')
            require({(source / p).resolve() for p in REQUIRED_SOURCES} <=
                    {Path(p).resolve() for p in command.get('inputs', []) if p.startswith('/')}, 'Build manifest not bound to current public source.')
            outputs = command.get('outputs', [])
            require(outputs and all(Path(p).resolve().is_relative_to(derived.resolve()) for p in outputs)
                    and any('Release-iphoneos' in p and 'iChart.build' in p for p in outputs), 'App compiler outputs outside this native Release build.')
            matched.append(sha(json.dumps(command, sort_keys=True).encode()))
        require(matched, 'No app compilation command in archive manifest.')
        result.append({'request_sha256': sha(path.read_bytes()), 'manifest_sha256': sha(manifest_path.read_bytes()),
                       'app_command_sha256': matched})
    require(result, 'No fresh native Release archive metadata.')
    return result


def validate_info(info, version=VERSION, build=BUILD):
    expected = {'CFBundleIdentifier': BUNDLE_ID, 'CFBundleExecutable': 'iChart',
                'CFBundleShortVersionString': version, 'CFBundleVersion': build,
                'SupabaseURL': PRODUCTION_URL, 'SupabaseAnonKey': '',
                'UIDeviceFamily': [2], 'CFBundleSupportedPlatforms': ['iPhoneOS'],
                'ITSAppUsesNonExemptEncryption': False}
    for name, value in expected.items():
        require(type(info.get(name)) is type(value) and info[name] == value, 'Baked public app setting mismatch: ' + name)
    require(info.get('TFInternalTestingOnly', False) is False, 'Actual app is marked TestFlight internal-only.')
    key = info.get('SupabasePublishableKey')
    require(isinstance(key, str) and re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]{16,}', key)
            and sha(key.encode()) == PRODUCTION_KEY_SHA256, 'Baked production client-key hash mismatch.')
    return {'bundle_id': BUNDLE_ID, 'version': version, 'build': build, 'host': PRODUCTION_URL,
            'publishable_key_sha256': PRODUCTION_KEY_SHA256, 'legacy_anon_empty': True, 'ipad_only': True,
            'actual_internal_only': info.get('TFInternalTestingOnly', False)}


def validate_export_options(options):
    expected = {'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
                'signingCertificate': 'Apple Distribution', 'teamID': TEAM,
                'provisioningProfiles': {BUNDLE_ID: 'iChart App Store'},
                'manageAppVersionAndBuildNumber': False, 'testFlightInternalTestingOnly': False}
    for name, value in expected.items():
        require(type(options.get(name)) is type(value) and options[name] == value, 'Public export option mismatch: ' + name)
    return {'internal_only': False, 'method': 'app-store-connect', 'distribution': 'manual App Store'}


def validate_inventory(names):
    for name in names:
        lower = name.lower()
        require(not any(marker in lower for marker in PARKED_MARKERS), 'Parked ML/research payload present.')
        require('.xctest' not in lower and not lower.startswith('plugins/') and '.appex/' not in lower
                and 'uifixture' not in lower and not lower.endswith('.storekit'), 'Unexpected QA/test/extension payload present.')
    return True


def parse_der(data, offset=0):
    require(offset + 2 <= len(data), 'Truncated active DER entitlements.')
    tag, length = data[offset:offset + 2]
    offset += 2
    if length & 128:
        count = length & 127
        require(0 < count <= 4 and offset + count <= len(data), 'Invalid DER length.')
        length = int.from_bytes(data[offset:offset + count], 'big')
        offset += count
    end = offset + length
    require(end <= len(data), 'Truncated DER payload.')
    payload = data[offset:end]
    if tag in (0x70, 0xB0, 0x30):
        children, current = [], 0
        while current < len(payload):
            child, current = parse_der(payload, current)
            children.append(child)
        return (tag, children), end
    if tag == 0x0C:
        return (tag, payload.decode('utf-8')), end
    if tag == 0x01 and payload in (b'\0', b'\xff'):
        return (tag, payload == b'\xff'), end
    if tag == 0x02 and payload == b'\x01':
        return (tag, 1), end
    raise GuardError('Unsupported active DER entitlement value.')


def active_entitlements(app):
    data = run('/usr/bin/codesign', '-d', '--der', '--entitlements', '-', str(app)).stdout
    (tag, children), end = parse_der(data)
    require(tag == 0x70 and end == len(data) and len(children) == 2 and children[0] == (0x02, 1)
            and children[1][0] == 0xB0, 'Invalid active DER dictionary.')
    values = {}
    for tag, fields in children[1][1]:
        require(tag == 0x30 and len(fields) == 2 and fields[0][0] == 0x0C
                and fields[1][0] in (0x0C, 0x01) and fields[0][1] not in values, 'Invalid active DER entry.')
        values[fields[0][1]] = fields[1][1]
    require(values == ACTIVE_ENTITLEMENTS and all(type(values[k]) is type(v) for k, v in ACTIVE_ENTITLEMENTS.items()), 'Unexpected active distribution entitlements.')
    return values


def uuid(path):
    output = run('/usr/bin/xcrun', 'dwarfdump', '--uuid', str(path)).stdout.decode()
    found = re.findall(r'UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)', output)
    require(len(found) == 1 and found[0][1] == 'arm64', 'Expected exactly one arm64 executable/dSYM UUID.')
    return found[0][0].upper()


def verify_app(app, version, build):
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    signer = run('/usr/bin/codesign', '-dv', '--verbose=4', str(app)).stderr.decode()
    require('Authority=Apple Distribution:' in signer and ('TeamIdentifier=' + TEAM + '\n') in signer,
            'App must have an Apple Distribution signature from the iChart team.')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    result = validate_info(info, version, build)
    result['active_der_entitlements'] = active_entitlements(app)
    profile_path = app / 'embedded.mobileprovision'
    profile = plistlib.loads(run('/usr/bin/security', 'cms', '-D', '-i', str(profile_path)).stdout)
    expiry = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
    require(expiry > datetime.datetime.now(datetime.timezone.utc), 'Distribution profile expired.')
    require(profile.get('Name') == 'iChart App Store' and profile.get('TeamIdentifier') == [TEAM]
            and 'ProvisionedDevices' not in profile and not profile.get('ProvisionsAllDevices'), 'Expected an App Store distribution profile without device scope.')
    grants = profile.get('Entitlements', {})
    require(all(type(grants.get(k)) is type(v) and grants[k] == v for k, v in ACTIVE_ENTITLEMENTS.items()), 'Distribution profile entitlement mismatch.')
    paths = list(app.rglob('*'))
    require(not any(p.is_symlink() for p in paths), 'Unexpected app symlink.')
    files = {p.relative_to(app).as_posix(): sha(p.read_bytes()) for p in paths if p.is_file()}
    validate_inventory(files)
    executable = (app / 'iChart').read_bytes()
    require(b'com.ichart.app.staging.fix036.' not in executable, 'Staging StoreKit product IDs present in public executable.')
    result.update({'strict_signature': True, 'profile_uuid': profile['UUID'], 'profile_expiry_utc': expiry.isoformat(),
                   'profile_sha256': sha(profile_path.read_bytes()), 'executable_sha256': sha(executable),
                   'uuid': uuid(app / 'iChart'), 'files': files})
    return result


def unpack_ipa(ipa, directory):
    with ZipFile(ipa) as package:
        entries = package.infolist()
        require(sum(e.file_size for e in entries) <= 512 * 1024 * 1024, 'IPA exceeds verification bound.')
        names = set()
        for entry in entries:
            name, mode = entry.filename, entry.external_attr >> 16
            path = PurePosixPath(name)
            require(name not in names and not path.is_absolute() and '..' not in path.parts and '\\' not in name
                    and not entry.flag_bits & 1 and stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), 'Unsafe or duplicate IPA entry.')
            require(not name.startswith('Payload/') or name == 'Payload/' or name.startswith('Payload/iChart.app/'), 'Unexpected IPA payload bundle.')
            names.add(name)
            if entry.is_dir() or not name.startswith('Payload/iChart.app/'):
                continue
            target = directory.joinpath(*path.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(package.read(entry))
            if mode & 0o111:
                target.chmod(0o755)
        validate_inventory(names)
    return directory / 'Payload/iChart.app', names



def unsigned_macho_prefix(data):
    require(data[:4] == b'\xcf\xfa\xed\xfe' and len(data) >= 32, 'Expected thin arm64 Mach-O.')
    count, size = struct.unpack_from('<II', data, 16)
    offset, signature = 32, None
    for _ in range(count):
        require(offset + 8 <= 32 + size <= len(data), 'Invalid Mach-O command table.')
        command, length = struct.unpack_from('<II', data, offset)
        require(length >= 8 and offset + length <= 32 + size, 'Invalid Mach-O load command.')
        if command == 0x1D:
            require(length == 16 and signature is None, 'Invalid Mach-O signature command.')
            signature = struct.unpack_from('<II', data, offset + 8)
        offset += length
    require(offset == 32 + size and signature is not None, 'Missing Mach-O code signature.')
    start, length = signature
    require(start >= offset and length > 0 and start + length == len(data), 'Unexpected Mach-O signature extent.')
    return data[:start]


def same_value(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(same_value(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(same_value(a, b) for a, b in zip(left, right))
    return left == right


def seal_without_info(app):
    seal = plistlib.loads((app / '_CodeSignature/CodeResources').read_bytes())
    for section in ('files', 'files2'):
        entry = seal.get(section, {}).pop('Info.plist', None)
        if entry is None:
            continue
        data = (app / 'Info.plist').read_bytes()
        if isinstance(entry, bytes):
            require(entry == hashlib.sha1(data).digest(), 'Invalid Info.plist seal.')
        else:
            require(isinstance(entry, dict) and entry and set(entry) <= {'hash', 'hash2'}, 'Unclassified Info.plist seal.')
            require(('hash' not in entry or entry['hash'] == hashlib.sha1(data).digest()) and
                    ('hash2' not in entry or entry['hash2'] == hashlib.sha256(data).digest()), 'Invalid Info.plist seal hash.')
    return seal


def compare_export(archive_app, exported_app, archive_files, exported_files):
    require(archive_files.keys() == exported_files.keys(), 'Archive/IPA app file inventory differs.')
    changed = [p for p in archive_files if archive_files[p] != exported_files[p]]
    for name in changed:
        if name == 'Info.plist':
            require(same_value(plistlib.loads((archive_app / name).read_bytes()),
                               plistlib.loads((exported_app / name).read_bytes())), 'Export changed Info.plist values or types.')
        elif name == '_CodeSignature/CodeResources':
            require(same_value(seal_without_info(archive_app), seal_without_info(exported_app)), 'Export changed resource seals beyond Info serialization.')
        elif name == 'iChart':
            require(unsigned_macho_prefix((archive_app / name).read_bytes()) ==
                    unsigned_macho_prefix((exported_app / name).read_bytes()), 'Export changed executable bytes outside existing signature.')
        else:
            raise GuardError('Export changed an unclassified app resource.')
    return sorted(changed)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    pin_parser = sub.add_parser('pin')
    verify_parser = sub.add_parser('verify')
    for part in (pin_parser, verify_parser):
        part.add_argument('--source', type=Path, required=True)
        part.add_argument('--output', type=Path, required=True)
    verify_parser.add_argument('--source-pin', type=Path, required=True)
    verify_parser.add_argument('--archive', type=Path, required=True)
    verify_parser.add_argument('--derived-data', type=Path, required=True)
    verify_parser.add_argument('--build-log', type=Path, required=True)
    verify_parser.add_argument('--export-options', type=Path, required=True)
    verify_parser.add_argument('--ipa', type=Path, required=True)
    args = parser.parse_args(argv)
    source = args.source.resolve()
    current = snapshot_source(source)
    if args.mode == 'pin':
        write_json(args.output, {'schema': 1, 'pinned_at_utc': now(), 'source': str(source), 'snapshot': current})
        print('Public release source pin recorded.')
        return 0
    pin = json.loads(args.source_pin.read_text())
    require(pin.get('source') == str(source) and current == pin.get('snapshot'), 'Source/build inputs differ from prearchive pin.')
    pin_time = datetime.datetime.fromisoformat(pin['pinned_at_utc']).timestamp()
    compile_rows = compiler_evidence(args.build_log.read_text(), args.derived_data, source)
    metadata = build_metadata(source, args.derived_data, pin_time)
    options = validate_export_options(plistlib.loads(args.export_options.read_bytes()))
    apps = list((args.archive / 'Products/Applications').glob('*.app'))
    require(len(apps) == 1 and apps[0].name == 'iChart.app', 'Archive must contain exactly iChart.app.')
    archive_result = verify_app(apps[0], VERSION, BUILD)
    dsym_uuid = uuid(args.archive / 'dSYMs/iChart.app.dSYM/Contents/Resources/DWARF/iChart')
    with tempfile.TemporaryDirectory(prefix='ichart-public-ipa-') as temp:
        exported_app, names = unpack_ipa(args.ipa, Path(temp))
        exported_result = verify_app(exported_app, VERSION, BUILD)
        require(archive_result['uuid'] == exported_result['uuid'] == dsym_uuid, 'Archive/IPA/dSYM UUID mismatch.')
        export_changes = compare_export(apps[0], exported_app, archive_result['files'], exported_result['files'])
    require(snapshot_source(source) == current, 'Source changed during verification.')
    receipt = {'schema': 1, 'verified_at_utc': now(), 'passed': True,
               'source': {'head': current['head'], 'tree': current['tree'], 'input_count': len(current['files']),
                          'source_pin_sha256': sha(args.source_pin.read_bytes()), 'contracts': current['contracts']},
               'compiler': compile_rows, 'archive_build_metadata': metadata,
               'archive': archive_result, 'exported_app': exported_result, 'export_options': options,
               'export_options_sha256': sha(args.export_options.read_bytes()), 'ipa_sha256': sha(args.ipa.read_bytes()),
               'ipa_bytes': args.ipa.stat().st_size, 'dsym_uuid': dsym_uuid, 'classified_export_changes': export_changes,
               'limits': ['Internal QA audience is controlled separately in App Store Connect.',
                          'No Apple processing, TestFlight installation, backend policy or physical preservation claim.']}
    write_json(args.output, receipt)
    print('Public archive and IPA verification passed; receipt written.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (GuardError, KeyError, OSError, ValueError) as error:
        # Never echo subprocess output, app Info values or arbitrary compiler text.
        print('Public packaging verification failed: ' + (str(error) if isinstance(error, GuardError) else type(error).__name__), file=sys.stderr)
        sys.exit(1)
