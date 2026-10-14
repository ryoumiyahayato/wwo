"""Internal JSON formatting, explicit formats and formal supplement generation."""
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('historical_provenance_generator', ROOT / 'tools/provenance/generate_historical_provenance.py')
generator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = generator
SPEC.loader.exec_module(generator)

class HistoricalProvenanceEolContractTest(unittest.TestCase):
    def test_equivalent_internal_formats_generate_identical_catalogs(self):
        expected = generator.build()
        original = generator.local_path
        paths = [generator.POLITICAL_PATH, generator.SPATIAL_PATH, generator.POPULATION_PATH, generator.POPULATION_MANIFEST_PATH] + ['res://data/world_map/historical/' + item[0] for item in generator.SUPPLEMENTS]
        with tempfile.TemporaryDirectory() as tmp:
            replacements = {}
            for index, path in enumerate(paths):
                document = json.loads(original(path).read_text(encoding='utf-8'))
                replacements[path] = Path(tmp) / f'{index}.json'
                replacements[path].write_bytes(json.dumps(dict(reversed(list(document.items()))), ensure_ascii=False, indent=4).replace('\n', '\r\n').encode('utf-8'))
            with patch.object(generator, 'local_path', side_effect=lambda path: replacements.get(path, original(path))):
                self.assertEqual(generator.build(), expected)

    def test_outputs_are_current_and_repeated_serialization_is_identical(self):
        for name, document in zip(('historical_source_registry', 'historical_fact_evidence'), generator.build()):
            self.assertEqual(document, json.loads((ROOT / f'data/provenance/{name}.json').read_text(encoding='utf-8')))
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'output.json'
                generator.write_json(path, document)
                first = path.read_bytes()
                generator.write_json(path, document)
                self.assertEqual(first, path.read_bytes())
                self.assertNotIn(b'\r', first)

    def test_facts_cover_inputs_and_have_resolved_unique_source_bindings(self):
        registry, catalog = generator.build()
        sources = {source['source_id']: source for source in registry['sources']}
        facts = {fact['fact_id']: fact for fact in catalog['facts']}
        self.assertEqual(len(sources), len(registry['sources']))
        self.assertEqual(len(facts), len(catalog['facts']))
        for fact in facts.values():
            source = sources[fact['source_id']]
            for key, target in (('source_version', 'version'), ('source_locator', 'locator'), ('license', 'license')):
                self.assertEqual(fact[key], source[target])
            generator.valid_period(fact['observation_period']['from'], fact['observation_period']['to'])
            self.assertNotIn('input_hash', fact)
            self.assertNotIn('output_hash', fact)
        political = generator.read_json(generator.POLITICAL_PATH)
        self.assertEqual({fact['subject_id'] for fact in facts.values() if fact['domain'] == 'political_identity'}, {unit['id'] for unit in political['units']})
        for unit in political['units']:
            value = facts['political_identity:' + unit['id']]['value']
            self.assertEqual(value, {key: unit[key] for key in value})
        for _, subject, domain, _ in generator.SUPPLEMENTS:
            self.assertEqual(facts[domain + ':' + subject]['review_status'], 'APPROXIMATE')
        self.assertIn('political_identity:country_fra', facts)
        self.assertIn('political_identity:german_empire', facts)

    def test_population_bounds_and_unknown_nulls_are_preserved(self):
        _, catalog = generator.build()
        facts = {fact['fact_id']: fact for fact in catalog['facts']}
        population = generator.read_json(generator.POPULATION_PATH)
        indexes = {field: index for index, field in enumerate(population['field_order'])}
        expected_ids = set()
        for row in population['rows']:
            fact_id = 'population_aggregate:population:' + row[indexes['entity_id']]
            expected_ids.add(fact_id)
            fact = facts[fact_id]
            for target, field in (('value', 'population_value'), ('lower_bound', 'population_lower'), ('upper_bound', 'population_upper')):
                self.assertEqual(fact[target], row[indexes[field]])
            self.assertEqual(fact['review_status'], 'BOUNDED_ESTIMATE')
        self.assertEqual(expected_ids, {key for key in facts if key.startswith('population_aggregate:')})
        unknown = generator.assertion('unknown', None, 'persons', {'from': '1900-01-01', 'to': '1900-01-01'}, {'kind': 'UNKNOWN', 'id': 'unknown'})
        self.assertIsNone(unknown['value'])
        self.assertIsNone(unknown['lower_bound'])
        self.assertEqual(unknown['spatial_scope']['kind'], 'UNKNOWN')

    def test_invalid_versions_duplicates_dates_and_references_fail(self):
        with self.assertRaises(generator.ProvenanceSourceContractError):
            generator.require_schema({'schema_version': 999}, 'schema_version', 1)
        with self.assertRaises(generator.ProvenanceSourceContractError):
            generator.unique_records([{'id': 'same'}, {'id': 'same'}], 'id')
        for start, end in (('1900-02-30', '1900-03-01'), ('1901-01-01', '1900-01-01')):
            with self.assertRaises((ValueError, generator.ProvenanceSourceContractError)):
                generator.valid_period(start, end)
        original = generator.read_json
        def invalid_geometry(path):
            document = original(path)
            if path == generator.POLITICAL_PATH:
                document['units'][0]['geometry_feature_id'] = 'missing_geometry'
            return document
        with patch.object(generator, 'read_json', side_effect=invalid_geometry):
            with self.assertRaises(generator.ProvenanceSourceContractError):
                generator.build()
        def unsupported_manifest(path):
            document = original(path)
            if path == generator.POPULATION_MANIFEST_PATH:
                document['schema_id'] = 'unsupported_population_manifest'
            return document
        with patch.object(generator, 'read_json', side_effect=unsupported_manifest):
            with self.assertRaises(generator.ProvenanceSourceContractError):
                generator.build()

if __name__ == '__main__':
    unittest.main(verbosity=2)
