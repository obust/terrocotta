import tempfile
import unittest
from pathlib import Path

from example_dependencies import (
    dependency_source,
    discover_entrypoints,
    read_alias,
    replace_dependency,
    update_entrypoints,
)


class ExampleDependenciesTests(unittest.TestCase):
    def test_reads_and_replaces_local_or_published_source(self):
        for old in ["../package/main.roc", "https://example.com/v1/old.tar.zst"]:
            source = f'app [] {{ tc: "{old}", other: "keep" }}\n'
            self.assertEqual(dependency_source(source, "tc"), old)
            self.assertEqual(
                replace_dependency(source, "tc", "https://example.com/new.tar.zst"),
                'app [] { tc: "https://example.com/new.tar.zst", other: "keep" }\n',
            )

    def test_only_header_dependency_changes(self):
        source = '''# app [] { tc: "comment" }
app [main!] {
    rr: platform "platform.tar.zst",
    other: "{ tc: fake }",
    # tc: "also a comment",
    tc: # comment between the label and value
        "old.tar.zst",
}
record = { tc: "body stays" }
'''
        expected = source.replace('        "old.tar.zst",', '        "new.tar.zst",')
        self.assertEqual(replace_dependency(source, "tc", "new.tar.zst"), expected)

    def test_bad_headers_fail(self):
        for source in [
            'app [] {}\nx = { tc: "body" }',
            'app [] { tc: "one", tc: "two" }',
            'app [] { tc: platform "host" }',
            'app [] { tc: "unclosed"',
            "package [Example] {}",
        ]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                replace_dependency(source, "tc", "new")

    def test_alias_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                read_alias(root)
            path = root / ".package-alias"
            path.write_text("tc\n", encoding="utf-8")
            self.assertEqual(read_alias(root), "tc")
            for invalid in ["", "tc other", "tc\nother", "roc", "platform", "Bad", "p.*"]:
                path.write_text(invalid, encoding="utf-8")
                with self.subTest(alias=invalid), self.assertRaises(ValueError):
                    read_alias(root)

    def test_nested_discovery_and_atomic_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / "nested"
            nested.mkdir()
            first = root / "first.roc"
            second = nested / "main.roc"
            ignored = nested / "Module.roc"
            first.write_text('app [] { tc: "old" }', encoding="utf-8")
            second.write_text('app [] { tc: "old" }', encoding="utf-8")
            ignored.write_text("value = 1", encoding="utf-8")
            self.assertEqual(discover_entrypoints(root), [first, second])

            second.write_text("app [] {}", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "main.roc"):
                update_entrypoints([first, second], "tc", "new")
            self.assertEqual(first.read_text(encoding="utf-8"), 'app [] { tc: "old" }')

            second.write_text('app [] { tc: "old" }', encoding="utf-8")
            update_entrypoints([first, second], "tc", "new")
            self.assertEqual(first.read_text(encoding="utf-8"), 'app [] { tc: "new" }')
            self.assertEqual(second.read_text(encoding="utf-8"), 'app [] { tc: "new" }')


if __name__ == "__main__":
    unittest.main()
