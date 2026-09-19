#!/usr/bin/env python3
"""Regression tests for the cross-platform world-data path-order contract."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.world_data.build_batch2_artifacts import build_data_manifest
from tools.world_data.build_batch3_contracts import build_record_signatures
from tools.world_data.path_order import canonical_path_sort, canonical_relative_posix_path


class CanonicalPathOrderTests(unittest.TestCase):
    def test_mixed_case_paths_use_one_case_sensitive_posix_order(self) -> None:
        root = Path('/synthetic/repository')
        paths = [
            root / 'data/world_map/city_detail/index.json',
            root / 'data/world_map/city_detail/countries/foo.json',
            root / 'data/world_map/city_detail/LICENSE.json',
        ]
        ordered = [canonical_relative_posix_path(path, root) for path in canonical_path_sort(paths, root)]
        self.assertEqual(
            ordered,
            [
                'data/world_map/city_detail/LICENSE.json',
                'data/world_map/city_detail/countries/foo.json',
                'data/world_map/city_detail/index.json',
            ],
        )

    def test_batch2_and_batch3_are_insertion_order_independent(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = [
                root / 'data/world_map/city_detail/index.json',
                root / 'data/world_map/city_detail/countries/foo.json',
                root / 'data/world_map/city_detail/LICENSE.json',
            ]
            documents = [
                '{"id":"index","items":[1]}\n',
                '{"id":"foo","items":[2]}\n',
                '{"id":"license","items":[3]}\n',
            ]
            for path, text in zip(paths, documents):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding='utf-8', newline='\n')

            forward_data = build_data_manifest(root, paths)
            reverse_data = build_data_manifest(root, reversed(paths))
            self.assertEqual(forward_data['files'], reverse_data['files'])
            self.assertEqual(forward_data['dataset_sha256'], reverse_data['dataset_sha256'])

            forward_signatures = build_record_signatures(root, paths)
            reverse_signatures = build_record_signatures(root, reversed(paths))
            self.assertEqual(forward_signatures['files'], reverse_signatures['files'])
            self.assertEqual(
                forward_signatures['record_signature_digest'],
                reverse_signatures['record_signature_digest'],
            )


if __name__ == '__main__':
    unittest.main()
