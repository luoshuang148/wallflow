"""Exercise the localization checker against valid and intentionally broken tables."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest

from check_localization import arguments, check


class LocalizationCheckTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sources = self.root / 'Sources'
        self.sources.mkdir()
        self.resources = self.root / 'Resources'
        self.write('zh-Hans', [('sample.title', '标题 %@')])
        self.write('en', [('sample.title', 'Title %@')])

    def write(self, language, rows):
        path = self.resources / (language + '.lproj') / 'Localizable.strings'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('\n'.join(f'{json.dumps(k)} = {json.dumps(v)};' for k, v in rows), encoding='utf-8')

    def run_check(self):
        with redirect_stdout(io.StringIO()):
            check(self.resources, self.sources)

    def test_matching_tables_and_lookups_pass(self):
        (self.sources / 'Sample.swift').write_text('let title = L("sample.title")')
        self.run_check()

    def test_missing_key_fails(self):
        self.write('en', [('different.key', 'Title %@')])
        with self.assertRaisesRegex(ValueError, 'key mismatch'):
            self.run_check()

    def test_duplicate_key_fails_before_dictionary_could_hide_it(self):
        self.write('en', [('sample.title', 'Title %@'), ('sample.title', 'Again %@')])
        with self.assertRaisesRegex(ValueError, 'duplicate key'):
            self.run_check()

    def test_whitespace_value_fails(self):
        self.write('en', [('sample.title', ' \n\t')])
        with self.assertRaisesRegex(ValueError, 'empty value'):
            self.run_check()

    def test_missing_format_argument_fails(self):
        self.write('en', [('sample.title', 'Title')])
        with self.assertRaisesRegex(ValueError, 'format argument mismatch'):
            self.run_check()

    def test_wrong_format_argument_type_fails(self):
        self.write('en', [('sample.title', 'Title %d')])
        with self.assertRaisesRegex(ValueError, 'format argument mismatch'):
            self.run_check()

    def test_positional_reordering_preserves_argument_types(self):
        self.write('zh-Hans', [('sample.title', '%@ %ld')])
        self.write('en', [('sample.title', '%2$ld %1$@')])
        self.run_check()

    def test_missing_swift_lookup_fails(self):
        (self.sources / 'Sample.swift').write_text('let title = L("missing.key")')
        with self.assertRaisesRegex(ValueError, 'missing lookup'):
            self.run_check()

    def test_missing_embedded_javascript_lookup_fails(self):
        (self.sources / 'Sample.swift').write_text("return error('missing.key')")
        with self.assertRaisesRegex(ValueError, 'missing lookup'):
            self.run_check()

    def test_malformed_strings_syntax_fails(self):
        path = self.resources / 'en.lproj' / 'Localizable.strings'
        path.write_text('"sample.title" = "Title %@"')
        with self.assertRaisesRegex(ValueError, 'invalid .strings syntax'):
            self.run_check()

    def test_escaped_percent_is_not_an_argument(self):
        self.assertEqual(arguments('100%% %@'), arguments('%@'))


if __name__ == '__main__':
    unittest.main()
