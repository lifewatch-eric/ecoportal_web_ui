import importlib.util
import pathlib
import tempfile
import unittest
import sys
from unittest import mock

sys.dont_write_bytecode = True


class PublicRefreshTest(unittest.TestCase):
    def setUp(self):
        path = pathlib.Path(__file__).resolve().parents[2] / 'script/refresh_public_sparql.py'
        self.assertTrue(path.is_file(), 'A guarded refresh utility is required before scheduling')
        spec = importlib.util.spec_from_file_location('public_refresh', path)
        self.job = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.job)

    def row(self, s, p, value, kind='uri'):
        return {'s': {'type': 'uri', 'value': s}, 'p': {'type': 'uri', 'value': p}, 'o': {'type': kind, 'value': value}}

    def test_only_public_subjects_and_reachable_auxiliary_metadata_survive(self):
        j = self.job
        public, private = 'http://data.bioontology.org/ontologies/A', 'http://data.bioontology.org/ontologies/B'
        contact = 'http://example.org/contact'
        metadata = {
            j.ONTOLOGY: [self.row(public, 'type', 'Ontology'), self.row(private, 'type', 'Ontology'), self.row(private, 'viewingRestriction', 'private', 'literal')],
            j.SUBMISSION: [self.row(public + '/submissions/1', 'contact', contact), self.row(private + '/submissions/1', 'contact', 'private-contact')],
            j.METADATA + 'Contact': [self.row(contact, 'name', 'Public contact', 'literal'), self.row('private-contact', 'name', 'Private contact', 'literal')],
            j.METADATA + 'User': [self.row('user', 'passwordHash', 'never-public', 'literal')],
        }
        subjects, public_set = j.public_policy(metadata)
        self.assertEqual({public}, public_set)
        self.assertEqual({public}, subjects[j.ONTOLOGY])
        self.assertEqual({public + '/submissions/1'}, subjects[j.SUBMISSION])
        self.assertEqual({contact}, subjects[j.METADATA + 'Contact'])
        self.assertNotIn(j.METADATA + 'User', subjects)
        self.assertTrue(j.content_allowed(public + '/submissions/1', public_set))
        self.assertFalse(j.content_allowed(public + 'B/submissions/1', public_set))
        self.assertFalse(j.content_allowed(private + '/submissions/1', public_set))

    def test_iri_validation_rejects_update_injection(self):
        self.assertEqual('<http://example.org/g>', self.job.iri('http://example.org/g'))
        for value in ['http://example.org/> } DROP ALL', 'http://example.org/\n', 'relative']:
            with self.assertRaises(ValueError):
                self.job.iri(value)

    def test_failed_copy_restores_checkpoint_interval(self):
        j = self.job
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / 'source.db'
            source.write_bytes(b'private database')
            calls = []
            with mock.patch.object(j, 'sql', side_effect=lambda port, text: calls.append(text)), mock.patch.object(j, 'source_pid', return_value='123'), mock.patch.object(j.shutil, 'copyfile', side_effect=OSError('disk failure')):
                with self.assertRaises(OSError):
                    j.copy_snapshot(source, pathlib.Path(folder) / 'copy.db', 60)
            self.assertIn('checkpoint_interval (60);', calls[-1])

    def test_process_restart_discards_native_copy_and_restores_checkpointing(self):
        j = self.job
        with tempfile.TemporaryDirectory() as folder:
            source = pathlib.Path(folder) / 'source.db'
            source.write_bytes(b'private database')
            calls = []
            with mock.patch.object(j, 'sql', side_effect=lambda port, text: calls.append(text)), mock.patch.object(j, 'source_pid', side_effect=['123', '456']):
                with self.assertRaises(RuntimeError):
                    j.copy_snapshot(source, pathlib.Path(folder) / 'copy.db', 60)
            self.assertIn('checkpoint_interval (60);', calls[-1])

    def test_truncated_metadata_is_rejected(self):
        j = self.job
        with mock.patch.object(j, 'query', return_value=[self.row('public', 'type', 'Ontology')]), mock.patch.object(j, 'count', return_value=2):
            with self.assertRaises(RuntimeError):
                j.rows(18891, j.ONTOLOGY)

    def test_truncated_graph_inventory_is_rejected(self):
        j = self.job
        with mock.patch.object(j, 'query', side_effect=[[{'g': {'value': j.ONTOLOGY}}], [{'n': {'value': '2'}}]]):
            with self.assertRaises(RuntimeError):
                j.graphs(18891)

    def test_public_readiness_tolerates_startup_delay(self):
        j = self.job
        import urllib.error
        with mock.patch.object(j, 'query', side_effect=[urllib.error.URLError('starting'), [{'ready': {'value': '1'}}]]) as requests, mock.patch.object(j.time, 'sleep'):
            j.wait_public()
            self.assertEqual(2, requests.call_count)

    def test_metadata_is_fetched_across_result_limit(self):
        j = self.job
        expected = [self.row('subject-' + str(i), 'type', 'value-' + str(i)) for i in range(1001)]
        with mock.patch.object(j, 'count', return_value=1001), mock.patch.object(j, 'query', side_effect=[expected[:1000], expected[1000:]]):
            self.assertEqual(expected, j.rows(18891, j.SUBMISSION))

    def test_overlapping_pages_are_rejected(self):
        j = self.job
        page = [self.row('subject-' + str(i), 'type', 'value-' + str(i)) for i in range(1000)]
        with mock.patch.object(j, 'count', return_value=1001), mock.patch.object(j, 'query', side_effect=[page, page[:1]]):
            with self.assertRaises(RuntimeError):
                j.rows(18891, j.SUBMISSION)

    def test_native_paging_avoids_virtuoso_sorted_top_limit(self):
        j = self.job
        expected = [self.row('subject-' + str(i), 'type', 'value-' + str(i)) for i in range(10001)]
        def provider(port, text):
            offset = int(text.rsplit('OFFSET ', 1)[1])
            if 'ORDER BY' in text and offset + 1000 > 10000:
                raise RuntimeError('Virtuoso SR353: sorted TOP exceeds 10000')
            return expected[offset:offset + 1000]
        with mock.patch.object(j, 'count', return_value=10001), mock.patch.object(j, 'query', side_effect=provider):
            self.assertEqual(expected, j.rows(18891, j.SUBMISSION))

    def test_stopped_public_service_does_not_require_an_old_endpoint(self):
        j = self.job
        from types import SimpleNamespace
        with mock.patch.object(j.subprocess, 'run', return_value=SimpleNamespace(returncode=3)), mock.patch.object(j, 'rows', side_effect=AssertionError('Stopped endpoint must not be queried')):
            self.assertEqual((set(), False), j.previous_projection())


if __name__ == '__main__':
    unittest.main()
