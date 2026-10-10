import base64
import contextlib
import hashlib
import io
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.research import blind_ink_annotation as annotation
from ichart_recognition_ml.research.blind_ink_tool import entrypoint, render_review_page, validate_review_bundle
from test_study_import import packet_bytes, point, stroke


_DOM_HARNESS = r"""
const fs = require('fs'); const vm = require('vm');
const input = JSON.parse(fs.readFileSync(0,'utf8'));
const all = []; const ids = {};
class Element {
  constructor(tag) { this.tag=tag; this.children=[]; this.dataset={}; this.attributes={}; this.style={}; this.value=''; this.checked=false; this.disabled=false; this.textContent=''; all.push(this); }
  append(...items) { this.children.push(...items); }
  replaceChildren(...items) { this.children=items; }
  setAttribute(key,value) { this.attributes[key]=String(value); }
  click() { if (!this.disabled && this.onclick) this.onclick(); }
  remove() {} focus() { this.focused=true; }
}
for (const name of ['drawing','message','reviewer','groups','progress','group-selected','save-partition','save-unresolved','save-no-read','clear-selection','symbol','attestation','stroke-list','review-json','export-fallback']) ids[name]=new Element('div');
const document = {getElementById:id=>ids[id], createElement:tag=>new Element(tag), createElementNS:(ns,tag)=>new Element(tag),body:new Element('body'),querySelectorAll:selector=>all.filter(e=>selector==='[data-stroke]' ? 'stroke' in e.dataset : 'strokeButton' in e.dataset)};
let saved = null;
const url = {createObjectURL:blob=>{saved=blob;return 'blob:local-unit-test';},revokeObjectURL:()=>{}};
vm.runInNewContext(input.script,{document,URL:url,Blob,setTimeout:fn=>fn(),Set,console});
ids.reviewer.value=input.reviewer || '1'.repeat(64); ids.attestation.checked=input.attestation !== false; ids.symbol.value=input.symbol || '';
for (const operation of input.operations) {
  if (operation[0]==='select') all.find(e=>e.dataset.strokeButton===String(operation[1])).click();
  else if (operation[0]==='ungroup') ids.groups.children[operation[1]].children[1].click();
  else if (operation[0]==='input') { ids[operation[1]].value=operation[2]; ids[operation[1]].oninput(); }
  else ids[operation[0]].click();
}
(async()=>{console.log(JSON.stringify({download:saved ? await saved.text() : null,visibleExport:ids['review-json'].value,status:ids.message.textContent,progress:ids.progress.textContent,partitionDisabled:ids['save-partition'].disabled,paths:all.filter(e=>e.tag==='path' && e.attributes.stroke!=='transparent').map(e=>e.attributes.d)}));})().catch(e=>{console.error(e);process.exitCode=1;});
"""


class BlindInkToolTests(unittest.TestCase):
    def setUp(self):
        self.source = packet_bytes([
            stroke([point(0,0),point(8,10)],creation_time_offset=0.1),
            stroke([point(7,1),point(1,1)],creation_time_offset=0.2),
            stroke([point(20,3)],creation_time_offset=0.3),
        ])
        self.packet = annotation.make_ownership_packet(self.source)
        self.first = annotation.make_ownership_review(self.packet,'1'*64,[[0,1],[2]])
        self.second = annotation.make_ownership_review(self.packet,'2'*64,[[0,1],[2]])
        self.receipt = annotation.freeze_ownership(self.packet,self.first,self.second,writer_hash='0'*64)

    def browser_script(self,page,**options):
        node = shutil.which('node')
        self.assertIsNotNone(node,'The UI export gate requires an actual JavaScript runtime, not a skipped test.')
        script = re.search(r'<script>(.*?)</script>',page.decode(),re.S).group(1)
        result = subprocess.run([node,'-e',_DOM_HARNESS],input=json.dumps({'script':script,**options}),text=True,capture_output=True,check=True)
        return json.loads(result.stdout)

    def test_ownership_page_contains_only_validated_packet_and_hash_bound_script(self):
        page = render_review_page(self.packet,mode='ownership')
        text = page.decode()
        script = re.search(r'<script>(.*?)</script>',text,re.S).group(1)
        actual = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        self.assertIn("script-src 'sha256-"+actual+"'",text)
        self.assertIn("connect-src 'none'",text)
        self.assertNotIn('fetch(',script)
        self.assertNotIn('localStorage',script)
        self.assertNotIn('XMLHttpRequest',script)
        self.assertNotIn('writerIDHash',script)
        self.assertNotIn('"reviews":',script)
        self.assertNotIn('intendedChord',script)
        self.assertNotIn('canonicalCandidate',script)
        self.assertNotIn('profile',json.dumps(json.loads(self.packet)))

    def test_actual_javascript_ownership_export_is_accepted_without_rewriting_source(self):
        original = self.source
        result = self.browser_script(render_review_page(self.packet,mode='ownership'),operations=[['select',0],['select',1],['group-selected'],['select',2],['group-selected'],['save-partition']])
        exported = result['download'].encode()
        self.assertEqual(exported,self.first)
        self.assertEqual(result['visibleExport'].encode(),self.first)
        self.assertIn('Download requested',result['status'])
        self.assertNotIn('Review downloaded',result['status'])
        self.assertEqual(result['progress'],'3 / 3 strokes grouped')
        self.assertFalse(result['partitionDisabled'])
        annotation.freeze_ownership(self.packet,exported,self.second,writer_hash='0'*64)
        self.assertEqual(original,self.source)

    def test_javascript_refuses_missing_roles_attestation_and_incomplete_partition(self):
        page = render_review_page(self.packet,mode='ownership')
        for options in ({'reviewer':'name'},{'attestation':False}):
            with self.subTest(options=options):
                result = self.browser_script(page,operations=[['save-unresolved']],**options)
                self.assertIsNone(result['download'])
                self.assertTrue(result['status'])
        result = self.browser_script(page,operations=[['select',0],['group-selected'],['save-partition']])
        self.assertIsNone(result['download'])
        self.assertTrue(result['partitionDisabled'])

    def test_javascript_unresolved_and_ungroup_retain_every_index(self):
        page = render_review_page(self.packet,mode='ownership')
        result = self.browser_script(page,operations=[['save-unresolved']])
        self.assertEqual(result['download'].encode(),annotation.make_ownership_review(self.packet,'1'*64,outcome='unresolved'))
        self.assertEqual(result['progress'],'0 / 3 strokes grouped')
        result = self.browser_script(page,operations=[['select',0],['select',1],['group-selected'],['select',2],['group-selected'],['ungroup',0],['group-selected'],['save-partition']])
        self.assertEqual(result['download'].encode(),self.first)

    def test_editing_after_export_invalidates_visible_old_review(self):
        page = render_review_page(self.packet,mode='ownership')
        result = self.browser_script(page,operations=[['select',0],['select',1],['group-selected'],['select',2],['group-selected'],['save-partition'],['ungroup',0]])
        self.assertEqual(result['visibleExport'],'')
        self.assertTrue(result['partitionDisabled'])
        self.assertIn('Review changed',result['status'])
        identity = annotation.make_identity_packets(self.packet,self.receipt)[0]
        result = self.browser_script(render_review_page(identity,mode='identity'),symbol='B',operations=[['save-partition'],['input','symbol','G']])
        self.assertEqual(result['visibleExport'],'')
        self.assertIn('Review changed',result['status'])

    def test_empty_stroke_is_preserved_visible_and_never_partition_exported(self):
        source = packet_bytes([stroke([]),stroke([point(1,2)])])
        packet = annotation.make_ownership_packet(source)
        result = self.browser_script(render_review_page(packet,mode='ownership'),operations=[['select',0],['select',1],['group-selected'],['save-partition'],['save-unresolved']])
        self.assertTrue(result['partitionDisabled'])
        self.assertIn('',result['paths'])
        self.assertEqual(json.loads(result['download'])['outcome'],'unresolved')
        self.assertEqual(canonical_json_bytes(json.loads(packet)['trajectoryPacket']),source)

    def test_identity_page_only_one_group_and_raw_unicode_export_validates(self):
        packet = annotation.make_identity_packets(self.packet,self.receipt)[1]
        page = render_review_page(packet,mode='identity')
        self.assertNotIn('writerIDHash',page.decode())
        self.assertNotIn('reviewSHA256s',page.decode())
        result = self.browser_script(page,reviewer='3'*64,symbol='△',operations=[['save-partition']])
        self.assertEqual(result['download'].encode(),annotation.make_identity_review(packet,'3'*64,symbol='△'))
        self.assertEqual(len(result['paths']),1)
        self.assertEqual(len(json.loads(packet)['trajectoryPacket']['strokes']),1)

    def test_identity_javascript_rejects_full_chords_and_preserves_ambiguous_no_read(self):
        packet = annotation.make_identity_packets(self.packet,self.receipt)[0]
        page = render_review_page(packet,mode='identity')
        for symbol in ('Bb7','e\u0301','\u200b','\n',' '):
            with self.subTest(symbol=repr(symbol)):
                result = self.browser_script(page,symbol=symbol,operations=[['save-partition']])
                self.assertIsNone(result['download'])
        for button,outcome in (('save-unresolved','human-ambiguous'),('save-no-read','no-read')):
            result = self.browser_script(page,operations=[[button]])
            self.assertEqual(result['download'].encode(),annotation.make_identity_review(packet,'1'*64,outcome=outcome))

    def test_display_accepts_zero_extent_and_subnormal_geometry_without_inventing_packet_extent(self):
        for source in (packet_bytes([stroke([point(-0.0,0)])]),packet_bytes([stroke([point(0,0),point(5e-324,0)])])):
            packet = annotation.make_ownership_packet(source)
            page = render_review_page(packet,mode='ownership')
            result = self.browser_script(page,operations=[])
            self.assertNotIn('Infinity',result['paths'][0])
            self.assertNotIn('NaN',result['paths'][0])
            self.assertEqual(canonical_json_bytes(json.loads(packet)['trajectoryPacket']),source)

    def test_cli_complete_ownership_identity_freeze_flow_exclusive_and_receipted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'source.json'; source.write_bytes(self.source)
            first = root/'first.json'; first.write_bytes(self.first)
            second = root/'second.json'; second.write_bytes(self.second)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(entrypoint(['prepare-ownership','--trajectory-json',str(source),'--expected-source-sha256',hashlib.sha256(self.source).hexdigest(),'--output-dir',str(root/'owner')]),0)
                self.assertEqual(entrypoint(['freeze-ownership','--ownership-packet',str(root/'owner/ownership-packet.json'),'--first-review',str(first),'--second-review',str(second),'--writer-id-hash','0'*64,'--output-dir',str(root/'frozen')]),0)
                self.assertEqual(entrypoint(['prepare-identity','--ownership-packet',str(root/'owner/ownership-packet.json'),'--ownership-receipt',str(root/'frozen/ownership-receipt.json'),'--output-dir',str(root/'glyphs')]),0)
                glyph_path = sorted((root/'glyphs').glob('identity-*.json'))[0]
                glyph = glyph_path.read_bytes()
                first.write_bytes(annotation.make_identity_review(glyph,'3'*64,symbol='B'))
                second.write_bytes(annotation.make_identity_review(glyph,'4'*64,symbol='B'))
                self.assertEqual(entrypoint(['freeze-identity','--identity-packet',str(glyph_path),'--ownership-packet',str(root/'owner/ownership-packet.json'),'--ownership-receipt',str(root/'frozen/ownership-receipt.json'),'--first-review',str(first),'--second-review',str(second),'--output-dir',str(root/'identity-frozen')]),0)
            receipt = json.loads((root/'identity-frozen/identity-receipt.json').read_bytes())
            self.assertEqual(receipt['symbol'],'B')
            for directory in ('owner','frozen','glyphs','identity-frozen'):
                prepared = json.loads((root/directory/'prepared-receipt.json').read_bytes())
                self.assertIs(prepared['trainingEligible'],False)
                for name,digest in prepared['artifacts'].items():
                    self.assertEqual(hashlib.sha256((root/directory/name).read_bytes()).hexdigest(),digest)
            self.assertEqual(source.read_bytes(),self.source)
            with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                entrypoint(['prepare-ownership','--trajectory-json',str(source),'--expected-source-sha256',hashlib.sha256(self.source).hexdigest(),'--output-dir',str(root/'owner')])
            self.assertEqual((root/'owner/ownership-packet.json').read_bytes(),self.packet)

    def test_cli_wrong_digest_unresolved_or_unknown_packet_produces_no_complete_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'source.json'; source.write_bytes(self.source)
            with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                entrypoint(['prepare-ownership','--trajectory-json',str(source),'--expected-source-sha256','a'*64,'--output-dir',str(root/'wrong')])
            self.assertFalse((root/'wrong').exists())
            owner = root/'owner.json'; owner.write_bytes(self.packet)
            receipt = root/'receipt.json'
            unresolved = annotation.make_ownership_review(self.packet,'1'*64,outcome='unresolved')
            receipt.write_bytes(annotation.freeze_ownership(self.packet,unresolved,self.second,writer_hash='0'*64))
            with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                entrypoint(['prepare-identity','--ownership-packet',str(owner),'--ownership-receipt',str(receipt),'--output-dir',str(root/'blocked')])
            self.assertFalse((root/'blocked').exists())

    def test_bundle_verification_rejects_modified_artifact_or_added_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'source.json'; source.write_bytes(self.source)
            with contextlib.redirect_stdout(io.StringIO()):
                entrypoint(['prepare-ownership','--trajectory-json',str(source),'--expected-source-sha256',hashlib.sha256(self.source).hexdigest(),'--output-dir',str(root/'bundle')])
                self.assertEqual(entrypoint(['verify-bundle','--bundle-dir',str(root/'bundle')]),0)
            extra = root/'bundle/extra.json'; extra.write_bytes(b'{}')
            with self.assertRaisesRegex(ValueError,'missing or extra'):
                validate_review_bundle(root/'bundle')
            extra.unlink()  # Test-owned disposable file only.
            page = root/'bundle/ownership-review.html'; page.write_bytes(page.read_bytes()+b'changed')
            with self.assertRaisesRegex(ValueError,'digest mismatch'):
                validate_review_bundle(root/'bundle')

    def test_interrupted_publication_is_not_a_complete_bundle_and_source_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'source.json'; source.write_bytes(self.source)
            import os
            original_open = os.open
            def fail_page(path,*args,**kwargs):
                if str(path).endswith('ownership-review.html'):
                    raise OSError('simulated local write interruption')
                return original_open(path,*args,**kwargs)
            with mock.patch('ichart_recognition_ml.research.blind_ink_tool.os.open',side_effect=fail_page),contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                entrypoint(['prepare-ownership','--trajectory-json',str(source),'--expected-source-sha256',hashlib.sha256(self.source).hexdigest(),'--output-dir',str(root/'partial')])
            self.assertFalse((root/'partial/prepared-receipt.json').exists())
            with self.assertRaises(OSError):
                validate_review_bundle(root/'partial')
            self.assertEqual(source.read_bytes(),self.source)


if __name__ == '__main__':
    unittest.main()
