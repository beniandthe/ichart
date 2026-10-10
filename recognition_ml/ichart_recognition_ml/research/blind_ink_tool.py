"""Offline reviewer pages for engineering-only original-ink annotation.

Pages contain only one validated blind packet, no outcomes or recognizer output.
Browser drawing is a display transform. Downloads contain index/identity reviews,
never modified trajectories. Human independence and consent remain external facts.
"""

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
from typing import Mapping, Sequence

from ..contracts import canonical_json_bytes, strict_json_loads
from ..errors import ContractError
from ..study_import import MAXIMUM_CANONICAL_PACKET_BYTE_COUNT
from . import blind_ink_annotation as annotation


_SCRIPT = r"""
'use strict';
const packet = PACKET_VALUE;
const packetSHA = PACKET_SHA_VALUE;
const mode = MODE_VALUE;
const geometry = GEOMETRY_VALUE;
const svg = document.getElementById('drawing');
const message = document.getElementById('message');
const reviewer = document.getElementById('reviewer');
const selected = new Set();
const groups = [];
const hasEmptyStroke = geometry.some(stroke => !stroke.path);
const colors = ['#1670b8','#b34921','#277941','#8858a5','#886115','#287f83'];
const ns = 'http://www.w3.org/2000/svg';
function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value !== null && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map(k => JSON.stringify(k)+':'+canonical(value[k])).join(',') + '}';
  }
  return JSON.stringify(value);
}
function status(text) { message.textContent = text; }
function invalidateExport() {
  document.getElementById('review-json').value = '';
  document.getElementById('export-fallback').hidden = true;
  if (message.textContent.startsWith('Download requested')) status('Review changed. Export again to capture the current state.');
}
function owner(index) { return groups.findIndex(group => group.includes(index)); }
function refresh() {
  invalidateExport();
  for (const item of document.querySelectorAll('[data-stroke]')) {
    const index = Number(item.dataset.stroke);
    const group = owner(index);
    item.setAttribute('stroke', selected.has(index) ? '#111' : group < 0 ? '#9299a1' : colors[group % colors.length]);
    item.setAttribute('stroke-width', selected.has(index) ? '5' : '3');
    item.setAttribute('aria-pressed', String(selected.has(index)));
  }
  document.getElementById('groups').replaceChildren();
  groups.forEach((group, index) => {
    const row = document.createElement('div');
    const text = document.createElement('span');
    text.textContent = 'Group '+(index+1)+': strokes '+group.map(i => i+1).join(', ');
    row.append(text);
    const button = document.createElement('button');
    button.textContent = 'Ungroup';
    button.onclick = () => { group.forEach(i => selected.add(i)); groups.splice(index,1); refresh(); };
    row.append(button);
    document.getElementById('groups').append(row);
  });
  const assigned = groups.reduce((sum,group) => sum+group.length,0);
  document.getElementById('progress').textContent = assigned+' / '+geometry.length+' strokes grouped';
  document.getElementById('group-selected').disabled = selected.size === 0;
  document.getElementById('save-partition').disabled = hasEmptyStroke || assigned !== geometry.length;
  for (const item of document.querySelectorAll('[data-stroke-button]')) {
    item.setAttribute('aria-pressed',String(selected.has(Number(item.dataset.strokeButton))));
  }
}
function toggle(index) { selected.has(index) ? selected.delete(index) : selected.add(index); refresh(); }
geometry.forEach((stroke,index) => {
  if (mode === 'ownership') {
    const button = document.createElement('button');
    button.textContent = 'Stroke '+(index+1)+(stroke.path ? '' : ' (empty)');
    button.dataset.strokeButton = String(index);
    button.onclick = () => toggle(index);
    document.getElementById('stroke-list').append(button);
  }
  const item = document.createElementNS(ns,'path');
  item.setAttribute('d',stroke.path);
  item.setAttribute('fill','none');
  item.setAttribute('stroke-linecap','round');
  item.setAttribute('stroke-linejoin','round');
  item.setAttribute('stroke','#111');
  item.setAttribute('stroke-width','3');
  if (mode === 'ownership') {
    const hit = document.createElementNS(ns,'path');
    hit.setAttribute('d',stroke.path);
    hit.setAttribute('fill','none');
    hit.setAttribute('stroke','transparent');
    hit.setAttribute('stroke-width','16');
    hit.setAttribute('stroke-linecap','round');
    hit.style.cursor = 'pointer';
    hit.onclick = () => toggle(index);
    svg.append(hit);
    item.dataset.stroke = String(index);
    item.setAttribute('role','button');
    item.setAttribute('aria-label','Stroke '+(index+1));
    item.setAttribute('tabindex','0');
    item.style.cursor = 'pointer';
    item.onclick = () => toggle(index);
    item.onkeydown = event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); toggle(index); } };
  }
  svg.append(item);
});
function download(outcome) {
  if (!/^[0-9a-f]{64}$/.test(reviewer.value)) { status('Enter the assigned 64-character reviewer hash. Do not enter your name.'); reviewer.focus(); return; }
  if (!document.getElementById('attestation').checked) { status('Confirm the blind-review statement before downloading.'); return; }
  const review = {
    blindAttestation:true,
    outcome:outcome,
    packetSHA256:packetSHA,
    reviewerIDHash:reviewer.value,
    version:mode === 'ownership' ? 'blind-ink-ownership-review-v1' : 'blind-ink-identity-review-v1'
  };
  if (mode === 'ownership') {
    const assigned = groups.reduce((sum,group) => sum+group.length,0);
    if (outcome === 'partitioned' && (hasEmptyStroke || assigned !== geometry.length)) { status('Every original stroke must belong to exactly one group. Empty or uncertain ownership must stay unresolved.'); return; }
    review.originalIndexGroups = outcome === 'unresolved' ? null : groups.map(g => [...g].sort((a,b) => a-b)).sort((a,b) => a[0]-b[0]);
  } else {
    const symbol = document.getElementById('symbol').value;
    if (outcome === 'symbol' && (Array.from(symbol).length !== 1 || symbol !== symbol.normalize('NFC') || /[\p{Cc}\p{Cf}\p{Cs}\p{Cn}\p{Z}]/u.test(symbol))) {
      status('Enter one exact visible character. Do not enter a full chord or silently normalize its spelling. Use ambiguous/no-read when needed.'); return;
    }
    review.symbol = outcome === 'symbol' ? symbol : null;
  }
  const contents = canonical(review);
  document.getElementById('review-json').value = contents;
  document.getElementById('export-fallback').hidden = false;
  const url = URL.createObjectURL(new Blob([contents], {type:'application/json'}));
  const link = document.createElement('a');
  link.href = url; link.download = 'blind-'+mode+'-'+packetSHA.slice(0,12)+'.json';
  document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url),1000);
  status('Download requested. If your browser blocks it, copy the review JSON below. A coordinator must validate and reconcile the independent reviews. This does not teach the app.');
}
document.getElementById('save-unresolved').onclick = () => download(mode === 'ownership' ? 'unresolved' : 'human-ambiguous');
document.getElementById('save-partition').onclick = () => download(mode === 'ownership' ? 'partitioned' : 'symbol');
document.getElementById('save-no-read').onclick = () => download('no-read');
document.getElementById('group-selected').onclick = () => {
  const indexes = [...selected].sort((a,b) => a-b);
  for (let i=groups.length-1;i>=0;i--) { groups[i] = groups[i].filter(index => !selected.has(index)); if (!groups[i].length) groups.splice(i,1); }
  groups.push(indexes); selected.clear(); refresh();
};
document.getElementById('clear-selection').onclick = () => { selected.clear(); refresh(); };
reviewer.oninput = invalidateExport;
document.getElementById('symbol').oninput = invalidateExport;
document.getElementById('attestation').onchange = invalidateExport;
if (mode === 'ownership') {
  refresh();
  if (hasEmptyStroke) status('This preserved packet contains an empty stroke. Do not discard it or invent geometry; record ownership unresolved.');
}
else {
  document.getElementById('progress').textContent = 'One isolated original group';
  document.getElementById('save-partition').disabled = false;
}
"""


def _display_geometry(strokes) -> list:
    # Rendering coordinates only; source packets/exports retain exact bitstrings.
    xs = [p.x for stroke in strokes for p in stroke.points]
    ys = [p.y for stroke in strokes for p in stroke.points]
    left, top = min(xs), min(ys)
    extent = max(max(xs) - left, max(ys) - top)
    # Uniform fit to 800x420 including margin, not anisotropic stretch.
    def project(delta):
        return delta / extent * 320.0 if extent > 0 else 0.0
    x_offset = (800 - project(max(xs)-left)) / 2
    y_offset = (420 - project(max(ys)-top)) / 2
    result = []
    for stroke in strokes:
        points = [(x_offset+project(p.x-left), y_offset+project(p.y-top)) for p in stroke.points]
        if not points:
            result.append({'path':''})
            continue
        path = 'M' + ' L'.join(f'{x:.8g},{y:.8g}' for x,y in points)
        if len(points) == 1 or all(p == points[0] for p in points):
            # SVG needs a nonempty rendered segment for a round-capped point.
            # This is display-only; the packet remains zero extent.
            x,y = points[0]
            path = f'M{x:.8g},{y:.8g} l0.001,0'
        result.append({'path':path})
    return result


def render_review_page(packet_data: bytes, *, mode: str) -> bytes:
    if mode == 'ownership':
        packet, strokes = annotation.validate_ownership_packet(packet_data)
    elif mode == 'identity':
        packet, strokes = annotation.validate_identity_packet(packet_data)
    else:
        raise ValueError('mode must be ownership or identity')
    script = _SCRIPT.replace('PACKET_VALUE',canonical_json_bytes(packet).decode('utf-8'))
    script = script.replace('PACKET_SHA_VALUE',json.dumps(hashlib.sha256(packet_data).hexdigest()))
    script = script.replace('MODE_VALUE',json.dumps(mode))
    script = script.replace('GEOMETRY_VALUE',json.dumps(_display_geometry(strokes),separators=(',',':')))
    # No encoded trajectory string may turn into executable HTML/script content.
    script = script.replace('</','<\\/')
    import base64
    script_sha = base64.b64encode(hashlib.sha256(script.encode('utf-8')).digest()).decode('ascii')
    title = 'Group original strokes' if mode == 'ownership' else 'Read one isolated symbol'
    instructions = ('Select the strokes belonging to one visible character or symbol, then group them. '
                    'Use the ink alone, not an expected chord. Leave uncertain ownership unresolved.'
                    if mode == 'ownership' else
                    'Transcribe the exact visible character in this isolated group. '
                    'Do not infer it from a chord answer. Preserve ambiguity or no-read.')
    display = '' if mode == 'ownership' else 'hidden'
    identity_display = 'hidden' if mode == 'ownership' else ''
    page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'sha256-{script_sha}'; style-src 'unsafe-inline'; connect-src 'none'; img-src 'none'; base-uri 'none'; form-action 'none'">
<title>{html.escape(title)}</title><style>
*{{box-sizing:border-box}}body{{font:16px system-ui;margin:0;color:#17202b;background:#f4f6f8}}
main{{max-width:950px;margin:24px auto;padding:24px;background:white;border-radius:16px}}
h1{{font-size:26px;margin:0 0 12px}}p{{line-height:1.5}}svg{{width:100%;border:1px solid #ced4dc;background:#fff;border-radius:12px;max-height:420px}}
button,input,textarea{{font:inherit}}button{{padding:10px 14px;margin:5px 5px 5px 0;border:1px solid #bbc3cd;border-radius:8px;background:#fff;cursor:pointer}}
button:disabled{{opacity:.45;cursor:default}}input[type=text]{{display:block;width:100%;padding:10px;border:1px solid #a8b2c0;border-radius:7px;margin:8px 0 16px}}
label{{display:block;margin-top:16px}}#symbol{{max-width:160px;font-size:28px}}#groups>div{{display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #e2e6ea}}
textarea{{width:100%;min-height:120px;margin-top:8px;font:13px ui-monospace,monospace}}
.note{{font-size:14px;color:#596471}}[hidden]{{display:none!important}}#message{{min-height:3em}}.primary{{background:#126fb9;color:white;border-color:#126fb9}}
</style></head><body><main><h1>{title}</h1><p>{instructions}</p>
<p class="note">Engineering-only blind review. No recognizer guesses, expected answers or personal profiles. The page works offline and sends nothing.</p>
<svg id="drawing" viewBox="0 0 800 420" role="group" aria-label="Original handwriting strokes"></svg>
<p id="progress" aria-live="polite"></p>
<section {display}><div id="stroke-list" aria-label="Select original packet strokes"></div><button id="group-selected">Group selected strokes</button><button id="clear-selection">Clear selection</button><div id="groups"></div></section>
<section {identity_display}><label for="symbol">Exact visible character</label><input id="symbol" type="text" autocomplete="off" spellcheck="false" aria-label="Exact visible character"></section>
<label for="reviewer">Assigned reviewer hash</label><input id="reviewer" type="text" maxlength="64" autocomplete="off" spellcheck="false" placeholder="64 lowercase hexadecimal characters">
<label><input type="checkbox" id="attestation"> I used only the displayed ink; I have not seen the intended chord, recognizer outputs, other reviews or the writer’s personal profile for this sample.</label>
<p><button id="save-partition" class="primary">{'Download partition review' if mode == 'ownership' else 'Download symbol review'}</button><button id="save-unresolved">{'Ownership unresolved' if mode == 'ownership' else 'Human ambiguous'}</button><button id="save-no-read" {identity_display}>No read</button></p>
<section id="export-fallback" hidden><label for="review-json">Review JSON (copy if download is blocked)</label><textarea id="review-json" readonly spellcheck="false" aria-label="Review JSON"></textarea></section>
<p id="message" role="status"></p><p class="note">Display fitting does not rewrite source coordinates. A hash and checkbox do not prove reviewer independence, consent, or training eligibility. A coordinator must verify those separately.</p>
</main><script>{script}</script></body></html>'''
    return page.encode('utf-8')


def _read(path: Path, maximum=8*1024*1024) -> bytes:
    with path.open('rb') as handle:
        data = handle.read(maximum+1)
    if len(data) > maximum:
        raise ValueError('input exceeds byte budget')
    return data


def _publish(directory: Path, artifacts: Mapping[str, bytes]) -> None:
    # No overwrite, no traversal/remote writes, and validation precedes publication.
    directory.mkdir(mode=0o700)
    for name,data in artifacts.items():
        descriptor = os.open(directory/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(descriptor,'wb') as handle:
            handle.write(data)
    receipt = canonical_json_bytes({
        'version':'blind-ink-review-bundle-v1',
        'artifactKind':'engineering-only-blind-annotation-v1',
        'trainingEligible':False,
        'artifacts':{name:hashlib.sha256(data).hexdigest() for name,data in artifacts.items()},
    })
    descriptor = os.open(directory/'prepared-receipt.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'wb') as handle:
        handle.write(receipt)
    validate_review_bundle(directory)


def validate_review_bundle(directory: Path) -> dict:
    """Validate a complete receipt; a partial directory is not a prepared bundle."""
    data = _read(directory/'prepared-receipt.json')
    receipt = strict_json_loads(data.decode('utf-8'),'prepared-receipt.json')
    if canonical_json_bytes(receipt) != data or not isinstance(receipt,dict):
        raise ValueError('noncanonical prepared receipt')
    if set(receipt) != {'version','artifactKind','trainingEligible','artifacts'} or receipt['version'] != 'blind-ink-review-bundle-v1' or receipt['artifactKind'] != annotation.ARTIFACT_KIND or receipt['trainingEligible'] is not False:
        raise ValueError('invalid prepared receipt fields')
    artifacts = receipt['artifacts']
    if not isinstance(artifacts,dict) or not 1 <= len(artifacts) <= 512:
        raise ValueError('invalid prepared artifact count')
    import re
    for name,digest in artifacts.items():
        if re.fullmatch(r'(ownership-(packet|receipt)\.json|ownership-review\.html|identity-receipt\.json|identity-[0-9a-f]{64}\.(json|html))',name) is None:
            raise ValueError('invalid prepared artifact name')
        if not isinstance(digest,str) or re.fullmatch(r'[0-9a-f]{64}',digest) is None or hashlib.sha256(_read(directory/name)).hexdigest() != digest:
            raise ValueError('prepared artifact digest mismatch')
    if {entry.name for entry in directory.iterdir()} != set(artifacts)|{'prepared-receipt.json'}:
        raise ValueError('prepared directory has missing or extra artifacts')
    return receipt


def entrypoint(argv: Sequence[str] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action',required=True)
    owner = actions.add_parser('prepare-ownership')
    owner.add_argument('--trajectory-json',type=Path,required=True)
    owner.add_argument('--expected-source-sha256',required=True)
    owner.add_argument('--output-dir',type=Path,required=True)
    glyph = actions.add_parser('prepare-identity')
    glyph.add_argument('--ownership-packet',type=Path,required=True)
    glyph.add_argument('--ownership-receipt',type=Path,required=True)
    glyph.add_argument('--output-dir',type=Path,required=True)
    freeze = actions.add_parser('freeze-ownership')
    freeze.add_argument('--ownership-packet',type=Path,required=True)
    freeze.add_argument('--first-review',type=Path,required=True)
    freeze.add_argument('--second-review',type=Path,required=True)
    freeze.add_argument('--writer-id-hash',required=True)
    freeze.add_argument('--adjudication-review',type=Path)
    freeze.add_argument('--output-dir',type=Path,required=True)
    freeze_glyph = actions.add_parser('freeze-identity')
    freeze_glyph.add_argument('--identity-packet',type=Path,required=True)
    freeze_glyph.add_argument('--ownership-packet',type=Path,required=True)
    freeze_glyph.add_argument('--ownership-receipt',type=Path,required=True)
    freeze_glyph.add_argument('--first-review',type=Path,required=True)
    freeze_glyph.add_argument('--second-review',type=Path,required=True)
    freeze_glyph.add_argument('--adjudication-review',type=Path)
    freeze_glyph.add_argument('--output-dir',type=Path,required=True)
    verify = actions.add_parser('verify-bundle')
    verify.add_argument('--bundle-dir',type=Path,required=True)
    args = parser.parse_args(argv)
    try:
        if args.action == 'verify-bundle':
            receipt = validate_review_bundle(args.bundle_dir)
            print(json.dumps({'status':'validated-engineering-only-bundle','artifacts':len(receipt['artifacts']),'trainingEligible':False},sort_keys=True))
            return 0
        elif args.action == 'prepare-ownership':
            source = _read(args.trajectory_json,MAXIMUM_CANONICAL_PACKET_BYTE_COUNT)
            if hashlib.sha256(source).hexdigest() != args.expected_source_sha256:
                raise ValueError('source digest mismatch')
            packet = annotation.make_ownership_packet(source)
            artifacts = {'ownership-packet.json':packet,'ownership-review.html':render_review_page(packet,mode='ownership')}
        elif args.action == 'prepare-identity':
            owner_packet = _read(args.ownership_packet)
            receipt = _read(args.ownership_receipt)
            packets = annotation.make_identity_packets(owner_packet,receipt)
            artifacts = {}
            for packet in packets:
                opaque_id = hashlib.sha256(packet).hexdigest()
                artifacts[f'identity-{opaque_id}.json'] = packet
                artifacts[f'identity-{opaque_id}.html'] = render_review_page(packet,mode='identity')
        elif args.action == 'freeze-ownership':
            receipt = annotation.freeze_ownership(
                _read(args.ownership_packet),_read(args.first_review),_read(args.second_review),
                writer_hash=args.writer_id_hash,
                adjudication=_read(args.adjudication_review) if args.adjudication_review else None,
            )
            artifacts = {'ownership-receipt.json':receipt}
        else:
            owner_packet = _read(args.ownership_packet)
            owner_receipt = _read(args.ownership_receipt)
            source = annotation.validate_ownership_freeze(owner_packet,owner_receipt)
            receipt = annotation.freeze_identity(
                _read(args.identity_packet),_read(args.first_review),_read(args.second_review),
                writer_hash=source['writerIDHash'],
                ownership_reviewer_hashes=source['reviewerIDHashes'],
                ownership_packet_bytes=owner_packet,ownership_receipt_bytes=owner_receipt,
                adjudication=_read(args.adjudication_review) if args.adjudication_review else None,
            )
            artifacts = {'identity-receipt.json':receipt}
        _publish(args.output_dir,artifacts)
        print(json.dumps({'status':'prepared-engineering-only','artifacts':len(artifacts),'trainingEligible':False},sort_keys=True))
        return 0
    except (ContractError,OSError,ValueError) as error:
        parser.exit(2,str(error)+'\n')


if __name__ == '__main__':
    raise SystemExit(entrypoint())
