import copy
import unittest
from validate_town import validate_town, load

class TownContent(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate_town(load('lifecycle'),load('balance')),[])

    def test_reject_invalid_contracts(self):
        for case in ['cost','passive','missing_civic','furniture','site','revision','benefit','support','density','duplicate','tuning','use','civic_predecessor']:
            with self.subTest(case=case):
                d,b=load('lifecycle'),load('balance')
                t=d['town'];p=t['projects'][1]
                if case=='use':p['changes'][0]['after'][0]['use']='work'
                if case=='civic_predecessor':t['projects'][0]['requires']=[]
                if case=='cost':b['town_lifecycle']['projects']['town_civic']['wood']=0
                if case=='passive':b['town_lifecycle']['projects']['town_provision']['effects']['storage']=60
                if case=='missing_civic':p['requires']=[]
                if case=='furniture':p['changes'][0]['after'][0]['furniture'].pop(0)
                if case=='site':t['proposals'][0]['predecessor']='lifecycle_store'
                if case=='revision':p['changes'][0]['expected_revisions']['yk_house_04']=9
                if case=='benefit':p['presentation']['benefit']='Free supplies'
                if case=='support':t['transition']['readiness']='different_clock'
                if case=='density':p['changes'][0]['after'][0]['use']='dwelling'
                if case=='duplicate':t['projects'][2]=copy.deepcopy(p)
                if case=='tuning':b['town_lifecycle']['projects']['unknown']=b['town_lifecycle']['projects'].pop('town_civic')
                self.assertTrue(validate_town(d,b),case)

if __name__=='__main__':unittest.main()
