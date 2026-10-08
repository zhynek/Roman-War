import unittest
from validate_visual_commands import validate, load
from validate_town import validate_town


class IntegrationGuideData(unittest.TestCase):
    def test_current_guide_destinations(self):
        data = load('visual_commands')
        self.assertEqual(validate(data), [])
        self.assertEqual(len(data['lessons']), 11)
        self.assertEqual([x['destination'] for x in data['lessons'][5:]],
                         ['lifecycle'] * 3 + ['defense'] * 2 + ['aftermath'])

    def test_no_command_destinations(self):
        for destination in ['advance', 'commission', 'warfare_begin', 'missing']:
            with self.subTest(destination=destination):
                data = load('visual_commands')
                data['lessons'][0]['destination'] = destination
                self.assertTrue(validate(data))

    def test_related_places_are_bounded_presentation(self):
        data = load('lifecycle')
        self.assertEqual(validate_town(data, load('balance')), [])
        project = data['town']['projects'][2]
        self.assertEqual(project['asset'], 'stores')
        self.assertEqual(project['presentation']['related_assets'], ['homes'])
        for related in [['missing'], ['stores'], ['homes', 'homes'], 'homes']:
            with self.subTest(related=related):
                data = load('lifecycle')
                data['town']['projects'][2]['presentation']['related_assets'] = related
                self.assertTrue(validate_town(data, load('balance')))


if __name__ == '__main__':
    unittest.main()
