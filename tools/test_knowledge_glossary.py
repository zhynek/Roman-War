#!/usr/bin/env python3
"""Negative tests for parent knowledge wording; no game data is written."""
import copy
import json
import unittest

import jsonschema

import validate_data as validator


class KnowledgeGlossaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = json.loads((validator.DATA / "effects_glossary.json").read_text())
        cls.schema = json.loads((validator.SCHEMAS / "effects_glossary.schema.json").read_text())

    def setUp(self):
        self.content = copy.deepcopy(type(self).content)

    def test_authored_wording_is_complete(self):
        jsonschema.validate(self.content, self.schema)
        self.assertEqual(validator.knowledge_wording_errors(self.content["knowledge"]), [])

    def test_each_missing_kind_is_rejected(self):
        for kind in self.content["knowledge"]["blockers"]:
            with self.subTest(kind=kind):
                content = copy.deepcopy(self.content)
                del content["knowledge"]["blockers"][kind]
                with self.assertRaises(jsonschema.ValidationError):
                    jsonschema.validate(content, self.schema)
                self.assertTrue(validator.knowledge_wording_errors(content["knowledge"]))

    def test_unknown_kind_is_rejected(self):
        self.content["knowledge"]["blockers"]["invented_rule"] = "Invented"
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate(self.content, self.schema)
        self.assertTrue(validator.knowledge_wording_errors(self.content["knowledge"]))

    def test_unfillable_or_malformed_token_is_rejected(self):
        for line in ("{needs} {battles} won ({wrong} recorded)", "{needs} {battles} won ({have} recorded) {bad-token}",
                     "{needs} {battles} won ({have} recorded) {", "{needs} {battles} won ({have} recorded) }"):
            with self.subTest(line=line):
                self.content["knowledge"]["blockers"]["battles_won"] = line
                self.assertTrue(validator.knowledge_wording_errors(self.content["knowledge"]))

    def test_missing_required_fact_is_rejected(self):
        self.content["knowledge"]["blockers"]["building"] = "{building_kind} (tier {level})"
        self.assertTrue(validator.knowledge_wording_errors(self.content["knowledge"]))

    def test_caption_tokens_and_empty_wording_are_checked(self):
        self.content["knowledge"]["wants"] = "Wants: {unknown}"
        self.assertTrue(validator.knowledge_wording_errors(self.content["knowledge"]))
        self.content["knowledge"]["battle_one"] = ""
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate(self.content, self.schema)


if __name__ == "__main__":
    unittest.main()
