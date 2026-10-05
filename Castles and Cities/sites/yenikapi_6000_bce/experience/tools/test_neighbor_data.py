#!/usr/bin/env python3
import copy
import unittest
from validate_neighbors import load,validate
class NeighborData(unittest.TestCase):
    def setUp(self):self.c=load('neighbors');self.u=load('neighbors_ui');self.b=load('balance');self.g=load('governance')
    def errors(self):return validate(self.c,self.u,self.b,self.g)
    def test_valid(self):self.assertEqual(self.errors(),[])
    def test_reject_corruption(self):
        mutations=[lambda c:c.update(kind='historical'),lambda c:c.update(project_id='missing'),lambda c:c.update(meeting_at=[0,0]),lambda c:c['neighbors'][1].update(id=c['neighbors'][0]['id']),lambda c:c['neighbors'][0].update(duration=0),lambda c:c['neighbors'][0].update(food=9999),lambda c:c['neighbors'][0]['offer'].update(receive='gold'),lambda c:c['neighbors'][0]['aid'].update(amount=0),lambda c:c['neighbors'][0].update(unknown=1),lambda c:c['neighbors'][0].update(term_offset=99),lambda c:c['neighbors'][0].update(pressure=[1,2])]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.c=load('neighbors');mutation(self.c);self.assertTrue(self.errors())
    def test_tuning(self):
        for key,value in [('carriers',0),('leader_term',0),('max_loss_percent',101),('initial_escorts',99)]:
            with self.subTest(key=key):self.b=load('balance');self.b['neighbors'][key]=value;self.assertTrue(self.errors())
    def test_required_prose(self):
        del self.u['events']['contact_sent'];self.assertTrue(self.errors())
    def test_optional_chapter(self):
        self.g['tutorial_projects'].append(self.c['project_id']);self.assertTrue(self.errors())
if __name__=='__main__':unittest.main()
